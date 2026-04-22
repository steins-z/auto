import Foundation
import AppKit
import SwiftUI

/// Flattens annotations onto an NSImage for export.
public enum AnnotationExporter {

    /// Render the annotated image into a single NSImage.
    /// - Parameters:
    ///   - image: source image
    ///   - annotations: ordered annotations (drawn back-to-front)
    ///   - cropRect: optional crop in image coordinates (top-left origin)
    @MainActor
    public static func flatten(
        image: NSImage,
        annotations: [Annotation],
        cropRect: CGRect? = nil
    ) -> NSImage {
        // 1. Apply blur regions first (they require pixel data of the source image).
        let blurRects: [CGRect] = annotations.compactMap {
            if case .blur(let r) = $0.kind { return r } else { return nil }
        }
        let blurRadius: CGFloat = annotations.last(where: {
            if case .blur = $0.kind { return true } else { return false }
        })?.style.blurRadius ?? 12

        let baseImage = blurRects.isEmpty
            ? image
            : ImageEffects.applyBlurRegions(to: image, rects: blurRects, pixelRadius: blurRadius)

        // 2. Determine output size & origin
        let crop = cropRect?.standardized.intersection(CGRect(origin: .zero, size: image.size))
        let outSize = crop?.size ?? image.size
        guard outSize.width > 0, outSize.height > 0 else { return baseImage }

        // 3. Render base + vector annotations through a CGContext (so we can use
        //    SwiftUI ImageRenderer without view hierarchy dependencies).
        let scale = (NSScreen.main?.backingScaleFactor ?? 2.0)
        let pixelW = Int(outSize.width * scale)
        let pixelH = Int(outSize.height * scale)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelW, height: pixelH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return baseImage }

        // Flip so we can draw using top-left-origin image coordinates.
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0, y: outSize.height)
        ctx.scaleBy(x: 1, y: -1)

        // Draw base image (cropped if needed). NSImage drawing uses bottom-left origin
        // within its own draw call — but our context flip already handles that.
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        if let crop {
            let dst = CGRect(origin: .zero, size: outSize)
            let src = CGRect(x: crop.origin.x,
                             y: image.size.height - crop.maxY,
                             width: crop.width, height: crop.height)
            baseImage.draw(in: dst, from: src, operation: .copy, fraction: 1.0)
        } else {
            baseImage.draw(in: CGRect(origin: .zero, size: outSize))
        }
        NSGraphicsContext.restoreGraphicsState()

        // 4. Draw annotations via SwiftUI ImageRenderer at native scale, then
        //    composite onto the base.
        let overlay = renderAnnotationOverlay(
            annotations: annotations,
            size: outSize,
            originOffset: crop?.origin ?? .zero,
            scale: scale
        )
        if let overlay {
            // Re-flip when drawing the overlay because it was rendered top-left already.
            ctx.saveGState()
            ctx.translateBy(x: 0, y: outSize.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(overlay, in: CGRect(origin: .zero, size: outSize))
            ctx.restoreGState()
        }

        guard let cg = ctx.makeImage() else { return baseImage }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = outSize
        let result = NSImage(size: outSize)
        result.addRepresentation(rep)
        return result
    }

    /// Render only the annotation overlay (no source image).
    @MainActor
    private static func renderAnnotationOverlay(
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
            // Translate so image-space coordinates map into cropped output space.
            ctx.translateBy(x: -originOffset.x, y: -originOffset.y)
            for ann in annotations {
                if case .blur = ann.kind { continue } // already baked
                var c = ctx
                AnnotationRenderer.draw(ann, in: &c)
            }
        }
    }
}
