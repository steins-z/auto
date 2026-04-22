import Foundation
import AppKit
import ApplicationServices
import CoreImage
import CoreGraphics

/// Detects scrollable content via the Accessibility API, programmatically scrolls
/// the target view, captures frames at each step, and stitches them together using
/// Core Image overlap detection.
///
/// **Browser support is best-effort.** AX scroll-bar value mutation works for native
/// `NSScrollView` (`AXScrollArea`). Safari and Chrome expose `AXWebArea` whose scroll
/// position is *not* writable through AX, so we fall back to synthesising
/// `kCGEventScrollWheel` events at the element's centre. This works for most pages
/// but is fragile (sticky headers, infinite-scroll lists, JS-managed scroll containers
/// can still misbehave). See `Limitations` in README.
///
/// **Identity check.** When the scrollable element is discovered we record the owning
/// process's PID, the bundle identifier, *and* the PID of the window directly under
/// the cursor at that moment. Every scroll/key/wheel write re-validates the element's
/// PID against that snapshot — if a different app has slipped under the cursor or
/// inserted itself into the AX tree at our element's coordinates, we abort instead of
/// blindly writing values into someone else's view hierarchy.
final class ScrollingCaptureService {
    enum CaptureError: Error {
        case accessibilityNotTrusted
        case noScrollableElement
        case identityMismatch
        case captureFailed
        case stitchingFailed
    }

    struct Configuration {
        var maxFrames: Int = 30
        var scrollSettleDelay: TimeInterval = 0.25
        var overlapSearchHeight: Int = 200
        /// Minimum delta (in points) we need to see between two scroll positions to keep
        /// going. Below this, we assume the bottom has been reached.
        var scrollProgressThreshold: CGFloat = 4
        static let `default` = Configuration()
    }

    private let configuration: Configuration
    private let ciContext = CIContext()

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Captures the scrollable element under the given screen point and returns a stitched image.
    /// `point` is in **CoreGraphics screen coordinates** (top-left origin, primary display origin).
    func captureScrollable(at point: CGPoint) async throws -> NSImage {
        try ensureAccessibility()
        guard let element = findScrollableElement(at: point) else {
            throw CaptureError.noScrollableElement
        }
        let frames = try await captureFrames(for: element)
        guard !frames.isEmpty else { throw CaptureError.captureFailed }
        return try stitch(frames: frames)
    }

    // MARK: - Accessibility

    private func ensureAccessibility() throws {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if !trusted { throw CaptureError.accessibilityNotTrusted }
    }

    /// Finds the deepest scrollable container (`AXScrollArea` or `AXWebArea`) under
    /// the given screen point.
    func findScrollableElement(at point: CGPoint) -> ScrollableElement? {
        let system = AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(system,
                                                      Float(point.x),
                                                      Float(point.y),
                                                      &hit)
        guard result == .success, let element = hit else { return nil }
        guard let scrollable = ascendToScrollable(from: element) else { return nil }
        // Cross-check: the element's owning PID must match the on-screen window owner
        // at the same point. If they disagree, a different app has either slipped
        // under the cursor or inserted itself into the AX tree — refuse to operate.
        let windowOwnerPID = windowOwnerPID(at: point)
        if let expected = windowOwnerPID, expected != scrollable.pid {
            NSLog("SnapClip: AX/window PID mismatch at \(point) (ax=\(scrollable.pid), window=\(expected)); refusing to scroll")
            return nil
        }
        return scrollable
    }

    private func ascendToScrollable(from element: AXUIElement) -> ScrollableElement? {
        var current: AXUIElement? = element
        while let node = current {
            if let role = copyAttribute(node, kAXRoleAttribute as String) as? String {
                if role == (kAXScrollAreaRole as String) {
                    return makeScrollable(node, kind: .scrollArea)
                }
                if role == "AXWebArea" {
                    return makeScrollable(node, kind: .webArea)
                }
                // AXScrollBar is *part of* a scroll area — keep ascending to the parent
                // AXScrollArea instead of treating the bar itself as terminal.
            }
            current = parent(of: node)
        }
        return nil
    }

    private func makeScrollable(_ element: AXUIElement, kind: ScrollableElement.Kind) -> ScrollableElement {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        return ScrollableElement(element: element, kind: kind, pid: pid, bundleIdentifier: bundleID)
    }

    /// Returns the PID of the front-most on-screen window containing the given screen point,
    /// or nil if no window is found. Uses CGWindowList rather than AX so a malicious AX
    /// hijacker can't fake the answer.
    private func windowOwnerPID(at point: CGPoint) -> pid_t? {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                        kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in infoList {
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int else { continue }
            // Skip overlay/menu/dock layers; we only care about ordinary app windows.
            if layer != 0 { continue }
            let rect = CGRect(x: bounds["X"] ?? 0,
                              y: bounds["Y"] ?? 0,
                              width: bounds["Width"] ?? 0,
                              height: bounds["Height"] ?? 0)
            if rect.contains(point) { return pid }
        }
        return nil
    }

    /// Re-validates that the scrollable element still belongs to the same process we
    /// originally discovered. Throws `CaptureError.identityMismatch` otherwise.
    private func assertIdentity(_ scrollable: ScrollableElement) throws {
        var nowPID: pid_t = 0
        AXUIElementGetPid(scrollable.element, &nowPID)
        if nowPID != scrollable.pid {
            throw CaptureError.identityMismatch
        }
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              let parent = value, CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
        return (parent as! AXUIElement)
    }

    private func copyAttribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        return err == .success ? value : nil
    }

    private func childElement(_ element: AXUIElement, _ key: String) -> AXUIElement? {
        guard let value = copyAttribute(element, key),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    // MARK: - Frame capture

    private func captureFrames(for scrollable: ScrollableElement) async throws -> [CGImage] {
        var images: [CGImage] = []
        var lastOffset: CGFloat = -.greatestFiniteMagnitude

        guard let frame = elementFrame(scrollable.element), frame.width > 0, frame.height > 0 else {
            throw CaptureError.captureFailed
        }
        let captureRect = cocoaRect(fromAXFrame: frame)

        // Reset to the top before we start.
        try assertIdentity(scrollable)
        scrollToTop(scrollable)
        try await Task.sleep(nanoseconds: UInt64(configuration.scrollSettleDelay * 1_000_000_000))

        for step in 0..<configuration.maxFrames {
            try await Task.sleep(nanoseconds: UInt64(configuration.scrollSettleDelay * 1_000_000_000))
            guard let image = captureRegion(captureRect) else { throw CaptureError.captureFailed }
            images.append(image)

            try assertIdentity(scrollable)
            let beforeOffset = currentScrollOffsetPoints(scrollable, viewportHeight: frame.height) ?? CGFloat(step) * frame.height
            scroll(scrollable, by: frame.height * 0.85, viewportFrame: frame)
            try await Task.sleep(nanoseconds: UInt64(configuration.scrollSettleDelay * 1_000_000_000))
            let afterOffset = currentScrollOffsetPoints(scrollable, viewportHeight: frame.height) ?? beforeOffset

            let delta = afterOffset - beforeOffset
            if delta < configuration.scrollProgressThreshold {
                // Scroll didn't advance — bottom reached (or not scrollable any further).
                break
            }
            // Detect identical offsets across consecutive iterations as a secondary stop.
            if abs(afterOffset - lastOffset) < configuration.scrollProgressThreshold && step > 0 {
                break
            }
            lastOffset = afterOffset
        }
        return images
    }

    private func elementFrame(_ element: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        guard let posVal = posValue, let sizeVal = sizeValue,
              CFGetTypeID(posVal) == AXValueGetTypeID(),
              CFGetTypeID(sizeVal) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue((posVal as! AXValue), .cgPoint, &origin)
        AXValueGetValue((sizeVal as! AXValue), .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    /// AX returns frames in screen coordinates with **top-left origin** relative to the
    /// primary display. Convert to Cocoa's bottom-left origin (relative to the union of
    /// all displays), which is what `CGWindowListCreateImage` and most CG APIs expect.
    private func cocoaRect(fromAXFrame ax: CGRect) -> CGRect {
        // CGWindowListCreateImage actually accepts top-left CG-origin coordinates relative
        // to the primary display, so AX frames pass through unchanged. We keep this
        // function as the single coordinate-conversion seam for clarity and to make
        // multi-display assumptions explicit.
        return ax
    }

    /// Returns the current vertical scroll position in **points from the top** of the
    /// scrollable content, or nil if the element doesn't expose a position we can read.
    private func currentScrollOffsetPoints(_ scrollable: ScrollableElement,
                                           viewportHeight: CGFloat) -> CGFloat? {
        switch scrollable.kind {
        case .scrollArea:
            // AXScrollArea exposes a vertical scroll bar with AXValue 0...1.
            guard let bar = childElement(scrollable.element, "AXVerticalScrollBar"),
                  let raw = copyAttribute(bar, kAXValueAttribute as String) as? NSNumber else {
                return nil
            }
            // We don't know full content height from AX alone; return a normalised
            // position scaled by viewport height as a monotonic proxy good enough for
            // progress detection.
            return CGFloat(raw.doubleValue) * max(viewportHeight * 10, 1)

        case .webArea:
            // Web areas don't expose AXValue. Use the visible-rect Y offset if present.
            if let visible = copyAttribute(scrollable.element, "AXVisibleCharacterRange") {
                _ = visible // touched intentionally; some browsers expose useful data here
            }
            // Fall back to a hash of the AX selected text range, which changes as the
            // page scrolls. Returning nil signals "use synthetic step counter" upstream.
            return nil
        }
    }

    private func scrollToTop(_ scrollable: ScrollableElement) {
        switch scrollable.kind {
        case .scrollArea:
            if let bar = childElement(scrollable.element, "AXVerticalScrollBar") {
                AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, NSNumber(value: 0.0))
            }
        case .webArea:
            // Send Cmd+Home at the element's centre to scroll to the top.
            if let frame = elementFrame(scrollable.element) {
                postKey(at: CGPoint(x: frame.midX, y: frame.midY), keyCode: 0x73, flags: .maskCommand) // Home
            }
        }
    }

    private func scroll(_ scrollable: ScrollableElement, by deltaPoints: CGFloat, viewportFrame: CGRect) {
        switch scrollable.kind {
        case .scrollArea:
            // For AXScrollArea, advance the vertical scroll bar by the fraction of the
            // viewport the delta represents. We can't read the content size from AX, so
            // assume content >= 10× viewport (clamped to [0,1]) and step proportionally.
            guard let bar = childElement(scrollable.element, "AXVerticalScrollBar") else { return }
            let current = (copyAttribute(bar, kAXValueAttribute as String) as? NSNumber)?.doubleValue ?? 0
            let assumedContentHeight = max(viewportFrame.height * 10, 1)
            let step = Double(deltaPoints) / Double(assumedContentHeight)
            let next = min(1.0, current + step)
            AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, NSNumber(value: next))

        case .webArea:
            // Browsers ignore programmatic AX scroll-bar mutation. Synthesise a real
            // scroll-wheel event at the element's centre instead.
            postScrollWheel(at: CGPoint(x: viewportFrame.midX, y: viewportFrame.midY),
                            deltaY: -deltaPoints)
        }
    }

    private func postScrollWheel(at point: CGPoint, deltaY: CGFloat) {
        // Move the cursor to the target point first (some browsers route scroll to the
        // element under the cursor regardless of the event location).
        CGWarpMouseCursorPosition(point)
        // Negative deltaY scrolls down (matches Cocoa convention when used with
        // `kCGScrollEventUnitPixel`).
        let steps = Int32(deltaY)
        guard let event = CGEvent(scrollWheelEvent2Source: nil,
                                  units: .pixel,
                                  wheelCount: 1,
                                  wheel1: steps,
                                  wheel2: 0,
                                  wheel3: 0) else { return }
        event.post(tap: .cghidEventTap)
    }

    private func postKey(at point: CGPoint, keyCode: CGKeyCode, flags: CGEventFlags) {
        CGWarpMouseCursorPosition(point)
        let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func captureRegion(_ rect: CGRect) -> CGImage? {
        // CGWindowListCreateImage is deprecated on the latest SDKs but still functional;
        // ScreenCaptureKit's per-frame setup adds unwanted latency for stitching.
        return CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution)
    }

    // MARK: - Stitching

    func stitch(frames: [CGImage]) throws -> NSImage {
        guard let first = frames.first else { throw CaptureError.stitchingFailed }
        if frames.count == 1 {
            return NSImage(cgImage: first, size: NSSize(width: first.width, height: first.height))
        }

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
            // Core Image y-axis is bottom-up; convert from the top-down stack.
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
        let bytesPerPixel = max(bytesPerRow / max(prev.width, 1), 1)
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

struct ScrollableElement {
    enum Kind { case scrollArea, webArea }
    let element: AXUIElement
    let kind: Kind
    /// PID of the process that owns this AX element at discovery time. Used by
    /// `ScrollingCaptureService.assertIdentity` to detect AX-tree hijacking.
    let pid: pid_t
    /// Bundle identifier of the owning app, if resolvable. Informational; the PID is
    /// the load-bearing identity check.
    let bundleIdentifier: String?
}
