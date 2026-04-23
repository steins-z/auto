import Foundation
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Core Image effects used for blur/mosaic regions.
public enum ImageEffects {

    /// Hard cap on the pixellate filter's `scale` input. Without this a wildly
    /// large `pixelRadius` (or a high-DPI source) can drive Core Image into
    /// pathological allocation patterns.
    public static let maxPixellateScale: Float = 256

    /// Returns a new NSImage where each blur rect (in image coordinates, top-left origin)
    /// has been replaced with a pixelated/blurred version of that region. Stacked rects
    /// composite on top of one another so a region covered twice stays redacted.
    public static func applyBlurRegions(
        to image: NSImage,
        rects: [CGRect],
        pixelRadius: CGFloat = 12
    ) -> NSImage {
        guard !rects.isEmpty else { return image }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage else { return image }

        let pixelW = cg.width
        let pixelH = cg.height
        let pointSize = image.size
        guard pointSize.width > 0, pointSize.height > 0 else { return image }

        let scaleX = CGFloat(pixelW) / pointSize.width
        let scaleY = CGFloat(pixelH) / pointSize.height

        let ciContext = CIContext(options: nil)
        let baseCI = CIImage(cgImage: cg)

        var current = baseCI
        for rect in rects {
            let r = rect.standardized
            // Convert image-space (top-left origin) to CI space (bottom-left origin) in pixels.
            // Inset outward by 1px to prevent a hairline of unblurred pixels at the rect
            // edge after `.integral` rounding — important for a privacy/redaction tool.
            let pxRect = CGRect(
                x: r.origin.x * scaleX,
                y: (pointSize.height - r.maxY) * scaleY,
                width: r.size.width * scaleX,
                height: r.size.height * scaleY
            ).integral.insetBy(dx: -1, dy: -1)
                .intersection(baseCI.extent)
            guard pxRect.width > 1, pxRect.height > 1 else { continue }

            // Sample from `current` so subsequent blurs stack idempotently — a region
            // covered by two overlapping rects ends up *more* redacted, never reverted
            // to the original pixels.
            let cropped = current.cropped(to: pxRect)
            let pixellate = CIFilter.pixellate()
            pixellate.inputImage = cropped
            pixellate.center = CGPoint(x: pxRect.midX, y: pxRect.midY)
            pixellate.scale = min(maxPixellateScale,
                                  max(2, Float(pixelRadius * scaleX)))
            guard let out = pixellate.outputImage?.cropped(to: pxRect) else { continue }
            current = out.composited(over: current)
        }

        guard let outCG = ciContext.createCGImage(current, from: baseCI.extent) else { return image }
        let outRep = NSBitmapImageRep(cgImage: outCG)
        outRep.size = pointSize
        let result = NSImage(size: pointSize)
        result.addRepresentation(outRep)
        return result
    }

    /// Returns a fully pixellated copy of the image (no rect masking) — used by the
    /// live editor preview so blur regions look identical to the exported result.
    public static func pixellated(_ image: NSImage, pixelRadius: CGFloat) -> NSImage {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage else { return image }
        let pointSize = image.size
        guard pointSize.width > 0, pointSize.height > 0 else { return image }
        let scaleX = CGFloat(cg.width) / pointSize.width
        let baseCI = CIImage(cgImage: cg)
        let pixellate = CIFilter.pixellate()
        pixellate.inputImage = baseCI
        pixellate.center = CGPoint(x: baseCI.extent.midX, y: baseCI.extent.midY)
        pixellate.scale = min(maxPixellateScale,
                              max(2, Float(pixelRadius * scaleX)))
        guard let out = pixellate.outputImage?.cropped(to: baseCI.extent),
              let outCG = CIContext().createCGImage(out, from: baseCI.extent) else { return image }
        let outRep = NSBitmapImageRep(cgImage: outCG)
        outRep.size = pointSize
        let result = NSImage(size: pointSize)
        result.addRepresentation(outRep)
        return result
    }
}
