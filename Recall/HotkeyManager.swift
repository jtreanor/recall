import Carbon
import AppKit

final class HotkeyManager {
    private var eventHandler: EventHandlerRef?
    private var hotkeyRef: EventHotKeyRef?
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    func register() {
        if eventHandler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, userData -> OSStatus in
                    guard let userData else { return OSStatus(eventNotHandledErr) }
                    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                    DispatchQueue.main.async { manager.callback() }
                    return noErr
                },
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandler
            )
        }
        registerHotkey()
    }

    func reregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        registerHotkey()
    }

    func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    private func registerHotkey() {
        let keyCode = SettingsManager.shared.hotkeyKeyCode
        let modifiers = SettingsManager.shared.hotkeyModifiers
        let hotkeyID = EventHotKeyID(signature: fourCharCode("RCLV"), id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotkeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
    }

    deinit {
        unregister()
    }

    // Synchronously invoke the callback on the calling thread — for unit tests only.
    func fireForTesting() {
        callback()
    }
}

private func fourCharCode(_ s: String) -> OSType {
    var result: OSType = 0
    for scalar in s.unicodeScalars.prefix(4) {
        result = (result << 8) + OSType(scalar.value)
    }
    return result
}
