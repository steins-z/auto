import AppKit
import ScreenCaptureKit
import CoreGraphics

enum CaptureMode: Int, CaseIterable {
    case region, window, fullScreen

    var label: String {
        switch self {
        case .region: return "Region"
        case .window: return "Window"
        case .fullScreen: return "Full Screen"
        }
    }
}

@MainActor
final class CaptureController {
    private var overlayWindows: [OverlayWindow] = []
    private var previewWindows: [PreviewWindow] = []

    func beginCapture() {
        guard overlayWindows.isEmpty else { return }
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true)
                presentOverlays(content: content)
            } catch {
                NSLog("SnapClip: failed to fetch shareable content: \(error)")
                await PermissionService.shared.ensureScreenRecordingPermission()
            }
        }
    }

    private func presentOverlays(content: SCShareableContent) {
        for screen in NSScreen.screens {
            guard let overlay = OverlayWindow(screen: screen, content: content) else {
                NSLog("SnapClip: no SCDisplay matched NSScreen \(screen.localizedName); skipping")
                continue
            }
            overlay.onComplete = { [weak self] result in
                self?.dismissOverlays()
                if let result {
                    Task { await self?.handleCapture(result) }
                }
            }
            overlay.makeKeyAndOrderFront(nil)
            overlayWindows.append(overlay)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismissOverlays() {
        for w in overlayWindows { w.orderOut(nil) }
        overlayWindows.removeAll()
    }

    private func handleCapture(_ request: CaptureRequest) async {
        do {
            let image = try await ScreenCaptureService.shared.capture(request)
            await MainActor.run { self.showPreview(image) }
        } catch {
            NSLog("SnapClip: capture failed: \(error)")
        }
    }

    private func showPreview(_ image: CGImage) {
        let window = PreviewWindow(image: image)
        window.onClose = { [weak self, weak window] in
            guard let window else { return }
            self?.previewWindows.removeAll { $0 === window }
        }
        window.makeKeyAndOrderFront(nil)
        previewWindows.append(window)
        NSApp.activate(ignoringOtherApps: true)
    }
}
