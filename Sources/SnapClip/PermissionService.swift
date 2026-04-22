import AppKit
import ScreenCaptureKit

@MainActor
final class PermissionService {
    static let shared = PermissionService()

    func ensureScreenRecordingPermission() async {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Screen Recording Permission Required"
                alert.informativeText = "SnapClip needs Screen Recording permission to capture screenshots. Please enable it in System Settings → Privacy & Security → Screen Recording."
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}
