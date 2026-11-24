import Foundation
import Carbon.HIToolbox

/// System-wide keyboard shortcut via Carbon's RegisterEventHotKey.
/// Unlike an event tap, this needs no Accessibility or Input Monitoring permission.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    /// Default: ⌃⌥K
    static let defaultKeyCode = UInt32(kVK_ANSI_K)
    static let defaultModifiers = UInt32(controlKey | optionKey)

    init?(keyCode: UInt32 = HotKey.defaultKeyCode,
          modifiers: UInt32 = HotKey.defaultModifiers,
          action: @escaping () -> Void) {
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                // Carbon delivers application-target hot keys on the main thread.
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { hotKey.action() }
                return noErr
            },
            1, &spec, context, &handlerRef
        )
        guard installStatus == noErr else { return nil }

        let id = EventHotKeyID(signature: OSType(0x544E_4348), id: 1)   // 'TNCH'
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, id,
                                                 GetApplicationEventTarget(), 0, &hotKeyRef)
        // On failure deinit still runs and removes the handler.
        guard registerStatus == noErr else { return nil }
    }

    deinit {
        // Carbon refs are plain pointers; releasing them from deinit is safe.
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
