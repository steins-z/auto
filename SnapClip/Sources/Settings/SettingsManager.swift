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

    static let `default` = HotkeyBinding(keyCode: 7, modifierFlags: 0x100 | 0x200) // Cmd+Shift+X (approx)
}

enum SettingsKey {
    static let saveDirectoryBookmark = "snapclip.saveDirectoryBookmark"
    static let imageFormat = "snapclip.imageFormat"
    static let jpegQuality = "snapclip.jpegQuality"
    static let windowShadow = "snapclip.windowShadow"
    static let launchAtLogin = "snapclip.launchAtLogin"
    static let appearance = "snapclip.appearance"
    static let hotkey = "snapclip.hotkey"
}

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let defaults: UserDefaults

    @Published var saveDirectory: URL {
        didSet { persistBookmark(for: saveDirectory) }
    }
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
        }
    }
    @Published var appearance: AppearanceMode {
        didSet {
            defaults.set(appearance.rawValue, forKey: SettingsKey.appearance)
            NSApp?.appearance = appearance.nsAppearance
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
        self.saveDirectory = SettingsManager.resolveBookmark(defaults: defaults) ?? desktop

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
    }

    // MARK: - Security-scoped bookmarks for the save directory

    private func persistBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
            defaults.set(data, forKey: SettingsKey.saveDirectoryBookmark)
        } catch {
            // Fall back to plain path if bookmark creation fails (e.g. unsigned dev builds).
            defaults.set(url.path, forKey: SettingsKey.saveDirectoryBookmark)
        }
    }

    private static func resolveBookmark(defaults: UserDefaults) -> URL? {
        if let data = defaults.data(forKey: SettingsKey.saveDirectoryBookmark) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data,
                                  options: [.withSecurityScope],
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &stale) {
                return url
            }
        }
        if let path = defaults.string(forKey: SettingsKey.saveDirectoryBookmark) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
