import AppKit
import SwiftUI
import ScreenCaptureKit

final class OverlayWindow: NSWindow {
    var onComplete: ((CaptureRequest?) -> Void)?

    private let screenRef: NSScreen
    private let content: SCShareableContent
    private var hostingView: NSHostingView<OverlayRootView>?

    /// Returns nil if no SCDisplay matches the given NSScreen — caller should skip this screen
    /// rather than crashing.
    init?(screen: NSScreen, content: SCShareableContent) {
        let screenDisplayID = OverlayWindow.displayID(for: screen)
        guard let display = content.displays.first(where: { $0.displayID == screenDisplayID })
                ?? content.displays.first else {
            return nil
        }

        self.screenRef = screen
        self.content = content
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.hasShadow = false
        self.setFrame(screen.frame, display: true)

        let windows = content.windows.filter { screen.frame.intersects($0.frame) }

        let root = OverlayRootView(
            screenFrame: screen.frame,
            display: display,
            windows: windows,
            onComplete: { [weak self] req in self?.onComplete?(req) }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: screen.frame.size)
        hosting.autoresizingMask = [.width, .height]
        self.contentView = hosting
        self.hostingView = hosting
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
