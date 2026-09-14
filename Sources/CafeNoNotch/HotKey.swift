import AppKit
import Carbon.HIToolbox

/// Atalho global via Carbon (RegisterEventHotKey) — funciona sem permissão
/// de Acessibilidade, ao contrário de um monitor global de NSEvent.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onFire: () -> Void

    /// keyCode/modifiers em constantes do Carbon (ex.: kVK_ANSI_C, cmdKey|shiftKey).
    init?(keyCode: UInt32, modifiers: UInt32, onFire: @escaping () -> Void) {
        self.onFire = onFire

        let hotKeyID = EventHotKeyID(signature: fourCharCode("CFNC"), id: 1)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let this = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                this.onFire()
                return noErr
            },
            1, &eventType, selfPtr, &handlerRef
        )
        guard installStatus == noErr else { return nil }

        let regStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                            GetApplicationEventTarget(), 0, &ref)
        guard regStatus == noErr else { return nil }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

private func fourCharCode(_ s: String) -> OSType {
    var result: OSType = 0
    for ch in s.utf8.prefix(4) { result = (result << 8) + OSType(ch) }
    return result
}
