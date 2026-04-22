import Foundation
import AppKit
import SwiftUI

/// Bridges `NSImage` across actor boundaries on macOS 13, where `NSImage`
/// gained Sendable conformance only in macOS 14. The exporter only ever reads
/// from these images on a single thread at a time.
private struct SendableImage: @unchecked Sendable {
    let image: NSImage
}

private struct SendableCGImage: @unchecked Sendable {
    let image: CGImage?
}

/// Flattens annotations onto an NSImage for export.
public enum AnnotationExporter {

    /// Render the annotated image into a single NSImage.
    /// CI/CGContext composition runs off the main actor; only the SwiftUI
    /// `ImageRenderer` overlay pass hops back to main (it is `@MainActor`).
    public static func flatten(
        image: NSImage,
        annotations: [Annotation],
        cropRect: CGRect? = nil
    ) async -> NSImage {
        // 1. Apply blur regions first (off-main; pure Core Image work).
        let blurRects: [CGRect] = annotations.compactMap {
            if case .blur(let r) = $0.kind { return r } else { return nil }
        }
        let blurRadius: CGFloat = annotations.last(where: {
            if case .blur = $0.kind { return true } else { return false }
        })?.style.blurRadius ?? 12

        let baseImage: NSImage = await Task.detached(priority: .userInitiated) { () -> SendableImage in
            let result = blurRects.isEmpty
                ? image
                : ImageEffects.applyBlurRegions(to: image, rects: blurRects, pixelRadius: blurRadius)
            return SendableImage(image: result)
        }.value.image

        // 2. Determine output size & origin
        let crop = cropRect?.standardized.intersection(CGRect(origin: .zero, size: image.size))
        let outSize = crop?.size ?? image.size
        guard outSize.width > 0, outSize.height > 0 else { return baseImage }

        // 3. Render the SwiftUI overlay on main (ImageRenderer is @MainActor).
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2.0 }
        let overlay: CGImage? = await renderAnnotationOverlay(
            annotations: annotations,
            size: outSize,
            originOffset: crop?.origin ?? .zero,
            scale: scale
        )

        // 4. Composite base + overlay into a CGContext off-main.
        let baseBox = SendableImage(image: baseImage)
        let sourceBox = SendableImage(image: image)
        let overlayBox = SendableCGImage(image: overlay)
        return await Task.detached(priority: .userInitiated) { () -> SendableImage in
            SendableImage(image: composite(
                base: baseBox.image,
                overlay: overlayBox.image,
                outSize: outSize,
                crop: crop,
                sourceSize: sourceBox.image.size,
                scale: scale
            ))
        }.value.image
    }

    /// Synchronous convenience for tests / callers that already hold the main actor.
    /// Performs all work on the caller's thread.
    @MainActor
    public static func flattenSync(
        image: NSImage,
        annotations: [Annotation],
        cropRect: CGRect? = nil
    ) -> NSImage {
        let blurRects: [CGRect] = annotations.compactMap {
            if case .blur(let r) = $0.kind { return r } else { return nil }
        }
        let blurRadius: CGFloat = annotations.last(where: {
            if case .blur = $0.kind { return true } else { return false }
        })?.style.blurRadius ?? 12
        let baseImage = blurRects.isEmpty
            ? image
            : ImageEffects.applyBlurRegions(to: image, rects: blurRects, pixelRadius: blurRadius)
        let crop = cropRect?.standardized.intersection(CGRect(origin: .zero, size: image.size))
        let outSize = crop?.size ?? image.size
        guard outSize.width > 0, outSize.height > 0 else { return baseImage }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let overlay = renderAnnotationOverlaySync(
            annotations: annotations,
            size: outSize,
            originOffset: crop?.origin ?? .zero,
            scale: scale
        )
        return composite(base: baseImage,
                         overlay: overlay,
                         outSize: outSize,
                         crop: crop,
                         sourceSize: image.size,
                         scale: scale)
    }

    // MARK: - Composite (thread-safe)

    private static func composite(
        base: NSImage,
        overlay: CGImage?,
        outSize: CGSize,
        crop: CGRect?,
        sourceSize: CGSize,
        scale: CGFloat
    ) -> NSImage {
        let pixelW = Int(outSize.width * scale)
        let pixelH = Int(outSize.height * scale)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelW, height: pixelH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return base }

        // Flip so we can draw using top-left-origin image coordinates.
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0, y: outSize.height)
        ctx.scaleBy(x: 1, y: -1)

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        if let crop {
            let dst = CGRect(origin: .zero, size: outSize)
            let src = CGRect(x: crop.origin.x,
                             y: sourceSize.height - crop.maxY,
                             width: crop.width, height: crop.height)
            base.draw(in: dst, from: src, operation: .copy, fraction: 1.0)
        } else {
            base.draw(in: CGRect(origin: .zero, size: outSize))
        }
        NSGraphicsContext.restoreGraphicsState()

        if let overlay {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: outSize.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(overlay, in: CGRect(origin: .zero, size: outSize))
            ctx.restoreGState()
        }

        guard let cg = ctx.makeImage() else { return base }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = outSize
        let result = NSImage(size: outSize)
        result.addRepresentation(rep)
        return result
    }

    // MARK: - Overlay rendering

    private static func renderAnnotationOverlay(
        annotations: [Annotation],
        size: CGSize,
        originOffset: CGPoint,
        scale: CGFloat
    ) async -> CGImage? {
        await MainActor.run {
            renderAnnotationOverlaySync(
                annotations: annotations,
                size: size,
                originOffset: originOffset,
                scale: scale
            )
        }
    }

    @MainActor
    private static func renderAnnotationOverlaySync(
        annotations: [Annotation],
        size: CGSize,
        originOffset: CGPoint,
        scale: CGFloat
    ) -> CGImage? {
        let renderer = ImageRenderer(content:
            AnnotationOverlayLayer(
                annotations: annotations,
                size: size,
                originOffset: originOffset
            )
            .frame(width: size.width, height: size.height)
        )
        renderer.scale = scale
        renderer.isOpaque = false
        return renderer.cgImage
    }
}

/// SwiftUI overlay used by the exporter to render vector annotations.
private struct AnnotationOverlayLayer: View {
    let annotations: [Annotation]
    let size: CGSize
    let originOffset: CGPoint

    var body: some View {
        Canvas { ctx, _ in
            ctx.translateBy(x: -originOffset.x, y: -originOffset.y)
            for ann in annotations {
                if case .blur = ann.kind { continue } // already baked
                var c = ctx
                AnnotationRenderer.draw(ann, in: &c)
            }
        }
    }
}
