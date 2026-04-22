import Foundation
import AppKit
import ApplicationServices
import CoreImage
import CoreGraphics

/// Detects scrollable content via the Accessibility API, programmatically scrolls
/// the target view, captures frames at each step, and stitches them together using
/// Core Image overlap detection.
final class ScrollingCaptureService {
    enum CaptureError: Error {
        case accessibilityNotTrusted
        case noScrollableElement
        case captureFailed
        case stitchingFailed
    }

    struct Configuration {
        var maxFrames: Int = 30
        var scrollSettleDelay: TimeInterval = 0.25
        var overlapSearchHeight: Int = 200
        static let `default` = Configuration()
    }

    private let configuration: Configuration
    private let ciContext = CIContext()

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Captures the scrollable element under the given screen point and returns a stitched image.
    func captureScrollable(at point: CGPoint) async throws -> NSImage {
        try ensureAccessibility()
        guard let scrollable = findScrollableElement(at: point) else {
            throw CaptureError.noScrollableElement
        }
        let frames = try await captureFrames(for: scrollable)
        guard !frames.isEmpty else { throw CaptureError.captureFailed }
        return try stitch(frames: frames)
    }

    // MARK: - Accessibility

    private func ensureAccessibility() throws {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if !trusted { throw CaptureError.accessibilityNotTrusted }
    }

    /// Walks the AX tree from the system-wide element down to find the deepest
    /// AXScrollArea or scrollable container under the given point.
    func findScrollableElement(at point: CGPoint) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(system,
                                                      Float(point.x),
                                                      Float(point.y),
                                                      &hit)
        guard result == .success, let element = hit else { return nil }
        return ascendToScrollable(from: element)
    }

    private func ascendToScrollable(from element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        while let node = current {
            if let role = copyAttribute(node, kAXRoleAttribute) as? String {
                if role == kAXScrollAreaRole as String { return node }
                // Web area: Safari/Chrome present a scrollable AXWebArea or AXGroup.
                if role == "AXWebArea" || role == "AXScrollBar" { return node }
            }
            current = copyAttribute(node, kAXParentAttribute) as! AXUIElement?
        }
        return nil
    }

    private func copyAttribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        return err == .success ? value : nil
    }

    // MARK: - Frame capture

    private func captureFrames(for element: AXUIElement) async throws -> [CGImage] {
        var images: [CGImage] = []
        var lastScrollOffset: CGFloat = -1

        let frame = elementFrame(element) ?? .zero
        guard frame.width > 0, frame.height > 0 else { throw CaptureError.captureFailed }

        for step in 0..<configuration.maxFrames {
            try await Task.sleep(nanoseconds: UInt64(configuration.scrollSettleDelay * 1_000_000_000))
            guard let image = captureRegion(frame) else { throw CaptureError.captureFailed }
            images.append(image)

            // Programmatically scroll: move the AX element's vertical scroll position.
            let offset = currentVerticalScrollOffset(element) ?? CGFloat(step) * frame.height
            if abs(offset - lastScrollOffset) < 1 && step > 0 {
                break // No more progress; bottom reached.
            }
            lastScrollOffset = offset
            scroll(element, by: frame.height * 0.85)
        }
        return images
    }

    private func elementFrame(_ element: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        guard let posVal = posValue, let sizeVal = sizeValue else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable force_cast
        AXValueGetValue(posVal as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        // swiftlint:enable force_cast
        return CGRect(origin: origin, size: size)
    }

    private func currentVerticalScrollOffset(_ element: AXUIElement) -> CGFloat? {
        // AXScrollArea exposes a vertical scrollbar with an AXValue 0...1.
        guard let bar = copyAttribute(element, "AXVerticalScrollBar") as! AXUIElement?,
              let valueRef = copyAttribute(bar, kAXValueAttribute) else { return nil }
        if let number = valueRef as? NSNumber { return CGFloat(truncating: number) }
        return nil
    }

    private func scroll(_ element: AXUIElement, by deltaY: CGFloat) {
        // For AXScrollArea, set the vertical scroll bar's value (0...1) incrementally.
        guard let bar = copyAttribute(element, "AXVerticalScrollBar") as! AXUIElement? else { return }
        let current = (copyAttribute(bar, kAXValueAttribute) as? NSNumber)?.doubleValue ?? 0
        let next = min(1.0, current + Double(deltaY) / 5000.0)
        let number = NSNumber(value: next)
        AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, number)
    }

    private func captureRegion(_ rect: CGRect) -> CGImage? {
        // Using deprecated CGWindowListCreateImage is fine for stitching frames; in production
        // we'd use ScreenCaptureKit, but it requires async setup per frame.
        return CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution)
    }

    // MARK: - Stitching

    func stitch(frames: [CGImage]) throws -> NSImage {
        guard let first = frames.first else { throw CaptureError.stitchingFailed }
        if frames.count == 1 { return NSImage(cgImage: first, size: .zero) }

        var pieces: [(image: CIImage, yOffset: CGFloat)] = [(CIImage(cgImage: first), 0)]
        var totalHeight = CGFloat(first.height)
        let width = CGFloat(first.width)

        for index in 1..<frames.count {
            let prev = frames[index - 1]
            let next = frames[index]
            let overlap = detectOverlap(prev: prev, next: next, searchHeight: configuration.overlapSearchHeight)
            let yOffset = totalHeight - CGFloat(overlap)
            pieces.append((CIImage(cgImage: next), yOffset))
            totalHeight = yOffset + CGFloat(next.height)
        }

        let canvasRect = CGRect(x: 0, y: 0, width: width, height: totalHeight)
        var composed = CIImage(color: .black).cropped(to: canvasRect)

        for piece in pieces {
            // Core Image y-axis is bottom-up; convert from top-down stack.
            let translatedY = totalHeight - piece.yOffset - piece.image.extent.height
            let translated = piece.image.transformed(by: CGAffineTransform(translationX: 0, y: translatedY))
            composed = translated.composited(over: composed)
        }

        guard let cg = ciContext.createCGImage(composed, from: canvasRect) else {
            throw CaptureError.stitchingFailed
        }
        return NSImage(cgImage: cg, size: NSSize(width: width, height: totalHeight))
    }

    /// Cheap overlap detection: slide the top `searchHeight` of `next` against the bottom
    /// of `prev` and find the offset that minimises mean squared pixel difference.
    private func detectOverlap(prev: CGImage, next: CGImage, searchHeight: Int) -> Int {
        let height = min(searchHeight, prev.height, next.height)
        guard height > 8 else { return 0 }
        guard let prevData = pixelData(prev), let nextData = pixelData(next) else { return 0 }
        let bytesPerRow = prev.bytesPerRow
        let bytesPerPixel = bytesPerRow / max(prev.width, 1)
        var bestOffset = 0
        var bestScore = Int.max
        let stride = max(1, height / 32)
        var offset = 8
        while offset < height {
            var score = 0
            var samples = 0
            var row = 0
            while row < height - offset {
                let prevRow = (prev.height - height + offset + row) * bytesPerRow
                let nextRow = row * bytesPerRow
                var col = 0
                while col < bytesPerRow {
                    let dr = Int(prevData[prevRow + col]) - Int(nextData[nextRow + col])
                    score += dr * dr
                    samples += 1
                    col += bytesPerPixel * 4
                }
                row += stride
            }
            let normalized = samples > 0 ? score / samples : Int.max
            if normalized < bestScore {
                bestScore = normalized
                bestOffset = offset
            }
            offset += stride
        }
        return bestOffset
    }

    private func pixelData(_ image: CGImage) -> [UInt8]? {
        guard let provider = image.dataProvider, let data = provider.data else { return nil }
        let length = CFDataGetLength(data)
        var bytes = [UInt8](repeating: 0, count: length)
        CFDataGetBytes(data, CFRange(location: 0, length: length), &bytes)
        return bytes
    }
}
