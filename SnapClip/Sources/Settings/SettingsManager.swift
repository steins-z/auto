import Foundation
import SwiftUI
import AppKit

enum ImageFormat: String, CaseIterable, Identifiable, Codable {
    case png, jpeg
    var id: String { rawValue }
    var fileExtension: String { self == .png ? "png" : "jpg" }
    var displayName: String { self == .png ? "PNG" : "JPEG" }
}

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

struct HotkeyBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifierFlags: UInt32

    /// Cmd+Shift+X. Modifier values match `NSEvent.ModifierFlags.deviceIndependentFlagsMask`.
    static let `default` = HotkeyBinding(
        keyCode: 7, // kVK_ANSI_X
        modifierFlags: UInt32(NSEvent.ModifierFlags.command.rawValue
                            | NSEvent.ModifierFlags.shift.rawValue)
    )
}

enum SettingsKey {
    static let saveDirectoryBookmark = "snapclip.saveDirectoryBookmark.v2" // bookmark Data only
    static let saveDirectoryPath = "snapclip.saveDirectoryPath"             // legacy plain path
    static let imageFormat = "snapclip.imageFormat"
    static let jpegQuality = "snapclip.jpegQuality"
    static let windowShadow = "snapclip.windowShadow"
    static let launchAtLogin = "snapclip.launchAtLogin"
    static let appearance = "snapclip.appearance"
    static let hotkey = "snapclip.hotkey"
}

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let defaults: UserDefaults

    /// URL the user picked. May be security-scoped — callers must wrap reads/writes in
    /// `withSaveDirectoryAccess { url in … }` so `startAccessingSecurityScopedResource()`
    /// is balanced with `stopAccessingSecurityScopedResource()`.
    @Published private(set) var saveDirectory: URL
    @Published var imageFormat: ImageFormat {
        didSet { defaults.set(imageFormat.rawValue, forKey: SettingsKey.imageFormat) }
    }
    @Published var jpegQuality: Double {
        didSet { defaults.set(jpegQuality, forKey: SettingsKey.jpegQuality) }
    }
    @Published var includeWindowShadow: Bool {
        didSet { defaults.set(includeWindowShadow, forKey: SettingsKey.windowShadow) }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: SettingsKey.launchAtLogin)
            LaunchAtLoginController.apply(enabled: launchAtLogin)
            // Re-sync against the system in case registration failed (e.g. unsigned build),
            // so the toggle reflects reality instead of the user's last click.
            let actual = LaunchAtLoginController.isEnabled
            if actual != launchAtLogin {
                launchAtLogin = actual
            }
        }
    }
    @Published var appearance: AppearanceMode {
        didSet {
            defaults.set(appearance.rawValue, forKey: SettingsKey.appearance)
            applyAppearance()
        }
    }
    @Published var hotkey: HotkeyBinding {
        didSet {
            if let data = try? JSONEncoder().encode(hotkey) {
                defaults.set(data, forKey: SettingsKey.hotkey)
            }
        }
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
        self.saveDirectory = SettingsManager.resolveSaveDirectory(defaults: defaults) ?? desktop

        let format = (defaults.string(forKey: SettingsKey.imageFormat)).flatMap(ImageFormat.init(rawValue:)) ?? .png
        self.imageFormat = format

        let qualityRaw = defaults.object(forKey: SettingsKey.jpegQuality) as? Double
        self.jpegQuality = qualityRaw ?? 0.9

        let shadowRaw = defaults.object(forKey: SettingsKey.windowShadow) as? Bool
        self.includeWindowShadow = shadowRaw ?? true

        self.launchAtLogin = defaults.bool(forKey: SettingsKey.launchAtLogin)

        let appearanceRaw = (defaults.string(forKey: SettingsKey.appearance)).flatMap(AppearanceMode.init(rawValue:)) ?? .system
        self.appearance = appearanceRaw

        if let data = defaults.data(forKey: SettingsKey.hotkey),
           let binding = try? JSONDecoder().decode(HotkeyBinding.self, from: data) {
            self.hotkey = binding
        } else {
            self.hotkey = .default
        }

        applyAppearance()
    }

    // MARK: - Save directory

    /// Update the save directory and persist a fresh security-scoped bookmark.
    /// Returns true on success. **Fails closed:** if a security-scoped bookmark cannot
    /// be created (typically a sandbox/entitlements problem), the change is rejected and
    /// an alert is shown rather than silently downgrading to a plain path that the
    /// sandbox would later block at write time.
    @discardableResult
    func setSaveDirectory(_ url: URL) -> Bool {
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
            defaults.set(data, forKey: SettingsKey.saveDirectoryBookmark)
            defaults.removeObject(forKey: SettingsKey.saveDirectoryPath)
            saveDirectory = url
            return true
        } catch {
            presentBookmarkFailureAlert(url: url, error: error)
            return false
        }
    }

    private func presentBookmarkFailureAlert(url: URL, error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't Use Folder"
        alert.informativeText = """
        SnapClip needs persistent access to "\(url.lastPathComponent)" but couldn't create a \
        security-scoped bookmark (\(error.localizedDescription)). The save folder hasn't been \
        changed. If SnapClip is sandboxed, grant access by re-selecting this folder; if you're \
        running an unsigned dev build, an entitlements/signing problem is likely the cause.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Run `body` with the save directory accessible under sandbox. Balances
    /// `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`.
    /// If the bookmark is stale, refreshes it silently on the way out (no UI alert —
    /// we already have a working URL, so a refresh failure shouldn't interrupt the save).
    @discardableResult
    func withSaveDirectoryAccess<T>(_ body: (URL) throws -> T) rethrows -> T {
        let (url, didStart, isStale) = resolveCurrentSaveDirectory()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
            if isStale { refreshBookmarkSilently(for: url) }
        }
        return try body(url)
    }

    private func refreshBookmarkSilently(for url: URL) {
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
            defaults.set(data, forKey: SettingsKey.saveDirectoryBookmark)
        } catch {
            NSLog("SnapClip: failed to refresh stale bookmark for \(url.path): \(error)")
        }
    }

    private func resolveCurrentSaveDirectory() -> (url: URL, didStart: Bool, stale: Bool) {
        if let data = defaults.data(forKey: SettingsKey.saveDirectoryBookmark) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data,
                                  options: [.withSecurityScope],
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &stale) {
                let started = url.startAccessingSecurityScopedResource()
                return (url, started, stale)
            }
        }
        return (saveDirectory, false, false)
    }

    private static func resolveSaveDirectory(defaults: UserDefaults) -> URL? {
        if let data = defaults.data(forKey: SettingsKey.saveDirectoryBookmark) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data,
                                  options: [.withSecurityScope],
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &stale) {
                return url
            }
        }
        if let path = defaults.string(forKey: SettingsKey.saveDirectoryPath) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    // MARK: - Appearance

    private func applyAppearance() {
        NSApp?.appearance = appearance.nsAppearance
        // Window override alone leaves child windows on the prior appearance until
        // they're rebuilt; nudge any existing windows so the override is immediate.
        for window in NSApp?.windows ?? [] {
            window.appearance = appearance.nsAppearance
        }
    }
}
