import Foundation
import CoreGraphics
import ScreenCaptureKit
import AppKit

struct CaptureRequest {
    enum Kind {
        case region(rect: CGRect, display: SCDisplay)
        case window(SCWindow)
        case fullScreen(SCDisplay)
    }
    let kind: Kind
}

@MainActor
final class ScreenCaptureService {
    static let shared = ScreenCaptureService()

    func capture(_ request: CaptureRequest) async throws -> CGImage {
        switch request.kind {
        case let .fullScreen(display):
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let cfg = baseConfiguration(display: display)
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)

        case let .window(window):
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let cfg = SCStreamConfiguration()
            let scale = displayScale(for: window) ?? 2
            cfg.width = Int(window.frame.width * scale)
            cfg.height = Int(window.frame.height * scale)
            cfg.showsCursor = false
            cfg.capturesAudio = false
            cfg.pixelFormat = kCVPixelFormatType_32BGRA
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)

        case let .region(rect, display):
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let cfg = baseConfiguration(display: display)
            cfg.sourceRect = rect
            let scale = scaleFactor(for: display)
            cfg.width = max(1, Int(rect.width * scale))
            cfg.height = max(1, Int(rect.height * scale))
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        }
    }

    private func baseConfiguration(display: SCDisplay) -> SCStreamConfiguration {
        let cfg = SCStreamConfiguration()
        let scale = scaleFactor(for: display)
        cfg.width = Int(CGFloat(display.width) * scale)
        cfg.height = Int(CGFloat(display.height) * scale)
        cfg.showsCursor = false
        cfg.capturesAudio = false
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        return cfg
    }

    private func scaleFactor(for display: SCDisplay) -> CGFloat {
        let id = display.displayID
        for screen in NSScreen.screens {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            if let num = screen.deviceDescription[key] as? NSNumber, num.uint32Value == id {
                return screen.backingScaleFactor
            }
        }
        return 2
    }

    private func displayScale(for window: SCWindow) -> CGFloat? {
        guard let displayID = window.owningApplication.flatMap({ _ in
            NSScreen.screens.first(where: { $0.frame.intersects(window.frame) })?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        }) else { return nil }
        _ = displayID
        return NSScreen.screens.first(where: { $0.frame.intersects(window.frame) })?.backingScaleFactor
    }
}
