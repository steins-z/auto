import SwiftUI
import AppKit
import Carbon.HIToolbox

struct PreferencesWindow: View {
    enum Tab: String, CaseIterable, Identifiable {
        case general, capture, appearance
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return "General"
            case .capture: return "Capture"
            case .appearance: return "Appearance"
            }
        }
        var systemImage: String {
            switch self {
            case .general: return "gearshape"
            case .capture: return "camera.viewfinder"
            case .appearance: return "paintbrush"
            }
        }
    }

    @StateObject private var settings = SettingsManager.shared
    @State private var selection: Tab = .general

    var body: some View {
        TabView(selection: $selection) {
            GeneralTab(settings: settings)
                .tabItem { Label(Tab.general.title, systemImage: Tab.general.systemImage) }
                .tag(Tab.general)
            CaptureTab(settings: settings)
                .tabItem { Label(Tab.capture.title, systemImage: Tab.capture.systemImage) }
                .tag(Tab.capture)
            AppearanceTab(settings: settings)
                .tabItem { Label(Tab.appearance.title, systemImage: Tab.appearance.systemImage) }
                .tag(Tab.appearance)
        }
        .frame(width: 480, height: 360)
        .padding(20)
    }
}

private struct GeneralTab: View {
    @ObservedObject var settings: SettingsManager
    @State private var recordingHotkey = false

    var body: some View {
        Form {
            Section("Hotkey") {
                HStack {
                    Text("Capture shortcut")
                    Spacer()
                    HotkeyRecorderButton(binding: $settings.hotkey, isRecording: $recordingHotkey)
                }
            }

            Section("Save Location") {
                HStack {
                    Text(settings.saveDirectory.path)
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…", action: chooseDirectory)
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectory = url
        }
    }
}

private struct CaptureTab: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        Form {
            Section("Image Format") {
                Picker("Format", selection: $settings.imageFormat) {
                    ForEach(ImageFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                if settings.imageFormat == .jpeg {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("JPEG quality")
                            Spacer()
                            Text("\(Int(settings.jpegQuality * 100))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.jpegQuality, in: 0...1)
                    }
                }
            }

            Section("Window Capture") {
                Toggle("Include window shadow", isOn: $settings.includeWindowShadow)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceTab: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Mode", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }
}

struct HotkeyRecorderButton: View {
    @Binding var binding: HotkeyBinding
    @Binding var isRecording: Bool

    var body: some View {
        Button(action: { isRecording.toggle() }) {
            Text(isRecording ? "Press keys…" : displayString(for: binding))
                .frame(minWidth: 120)
        }
        .background(KeyEventCatcher(isActive: isRecording) { keyCode, modifiers in
            binding = HotkeyBinding(keyCode: UInt32(keyCode), modifierFlags: UInt32(modifiers))
            isRecording = false
        })
    }

    private func displayString(for binding: HotkeyBinding) -> String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: UInt(binding.modifierFlags))
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(KeyCodeMap.string(for: Int(binding.keyCode)))
        return parts.joined()
    }
}

private struct KeyEventCatcher: NSViewRepresentable {
    var isActive: Bool
    var onKey: (Int, UInt) -> Void

    func makeNSView(context: Context) -> NSView { CatchingView(onKey: onKey) }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? CatchingView else { return }
        view.onKey = onKey
        if isActive { view.window?.makeFirstResponder(view) }
    }

    private final class CatchingView: NSView {
        var onKey: (Int, UInt) -> Void
        init(onKey: @escaping (Int, UInt) -> Void) {
            self.onKey = onKey
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
            onKey(Int(event.keyCode), mods)
        }
    }
}

enum KeyCodeMap {
    static func string(for keyCode: Int) -> String {
        switch keyCode {
        case kVK_ANSI_A: return "A"; case kVK_ANSI_B: return "B"; case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"; case kVK_ANSI_E: return "E"; case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"; case kVK_ANSI_H: return "H"; case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"; case kVK_ANSI_K: return "K"; case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"; case kVK_ANSI_N: return "N"; case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"; case kVK_ANSI_Q: return "Q"; case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"; case kVK_ANSI_T: return "T"; case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"; case kVK_ANSI_W: return "W"; case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"; case kVK_ANSI_Z: return "Z"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Escape: return "⎋"
        default: return "Key\(keyCode)"
        }
    }
}
