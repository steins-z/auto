import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKeyManager: HotKeyManager?
    private var _captureController: CaptureController?

    @MainActor
    private var captureController: CaptureController {
        if let c = _captureController { return c }
        let c = CaptureController()
        _captureController = c
        return c
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.setActivationPolicy(.accessory)
            self.setupStatusItem()
            self.setupHotKey()
            Task { await PermissionService.shared.ensureScreenRecordingPermission() }
        }
    }

    @MainActor
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "SnapClip")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        let newItem = NSMenuItem(title: "New Screenshot", action: #selector(newScreenshot), keyEquivalent: "x")
        newItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(newItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit SnapClip", action: #selector(quit), keyEquivalent: "q"))
        for mi in menu.items { mi.target = self }
        item.menu = menu
        self.statusItem = item
    }

    @MainActor
    private func setupHotKey() {
        let manager = HotKeyManager()
        manager.onTrigger = { [weak self] in
            Task { @MainActor in self?.captureController.beginCapture() }
        }
        manager.register(keyCode: 7, modifiers: [.maskCommand, .maskShift]) // 7 = "x"
        self.hotKeyManager = manager
    }

    @MainActor
    @objc private func newScreenshot() {
        captureController.beginCapture()
    }

    @objc private func openPreferences() {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
