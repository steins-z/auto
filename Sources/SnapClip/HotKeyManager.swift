import Cocoa
import Carbon.HIToolbox

/// Global hotkey via Carbon's `RegisterEventHotKey`. Unlike a CGEvent tap this does not
/// require Accessibility permission and fails loudly if registration is rejected.
final class HotKeyManager {
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private static let signature: OSType = {
        let chars: [UInt8] = Array("SCLP".utf8)
        return (OSType(chars[0]) << 24) | (OSType(chars[1]) << 16) | (OSType(chars[2]) << 8) | OSType(chars[3])
    }()
    private static var managerRegistry: [UInt32: HotKeyManager] = [:]
    private static var nextID: UInt32 = 1

    private var hotKeyID: UInt32 = 0

    /// Register a global hotkey. `keyCode` is a Carbon virtual key code (e.g. `kVK_ANSI_X`).
    /// `modifiers` is a Carbon modifier mask (e.g. `cmdKey | shiftKey`).
    /// Returns true on success.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        unregister()

        let id = HotKeyManager.nextID
        HotKeyManager.nextID += 1
        self.hotKeyID = id
        HotKeyManager.managerRegistry[id] = self

        installHandlerIfNeeded()

        let hkID = EventHotKeyID(signature: HotKeyManager.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            HotKeyManager.managerRegistry.removeValue(forKey: id)
            NSLog("SnapClip: RegisterEventHotKey failed (status=\(status))")
            DispatchQueue.main.async { self.presentRegistrationFailedAlert(status: status) }
            return false
        }
        self.hotKeyRef = ref
        return true
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if hotKeyID != 0 {
            HotKeyManager.managerRegistry.removeValue(forKey: hotKeyID)
            hotKeyID = 0
        }
    }

    deinit { unregister() }

    private static var sharedHandlerInstalled = false
    private func installHandlerIfNeeded() {
        guard !HotKeyManager.sharedHandlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, _ -> OSStatus in
            guard let eventRef else { return noErr }
            var hkID = EventHotKeyID()
            let status = GetEventParameter(eventRef, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if status == noErr,
               let manager = HotKeyManager.managerRegistry[hkID.id] {
                DispatchQueue.main.async { manager.onTrigger?() }
            }
            return noErr
        }, 1, &spec, nil, nil)
        HotKeyManager.sharedHandlerInstalled = true
    }

    private func presentRegistrationFailedAlert(status: OSStatus) {
        let alert = NSAlert()
        alert.messageText = "Hotkey Unavailable"
        alert.informativeText = "SnapClip could not register ⌘⇧X as a global hotkey (error \(status)). Another app may already own this shortcut. You can still trigger captures from the menu bar icon."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
