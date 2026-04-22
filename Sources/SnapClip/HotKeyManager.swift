import Cocoa
import CoreGraphics

/// Global hotkey via CGEvent tap. Watches keyDown events and triggers a callback when
/// the configured key + modifiers are pressed.
final class HotKeyManager {
    var onTrigger: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyCode: CGKeyCode = 7 // "x"
    private var modifiers: CGEventFlags = [.maskCommand, .maskShift]

    func register(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        installTap()
    }

    private func installTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(refcon).takeUnretainedValue()
                if type == .keyDown {
                    let kc = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                    let flags = event.flags
                    let relevantMask: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
                    if kc == manager.keyCode && (flags.intersection(relevantMask) == manager.modifiers) {
                        DispatchQueue.main.async { manager.onTrigger?() }
                        return nil
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            NSLog("SnapClip: failed to create event tap (Accessibility permission required)")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.eventTap = tap
        self.runLoopSource = source
    }

    deinit {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }
}
