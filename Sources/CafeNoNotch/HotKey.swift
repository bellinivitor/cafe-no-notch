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

/// Converte os modificadores do NSEvent para bits do Carbon.
func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var m: UInt32 = 0
    if flags.contains(.command) { m |= UInt32(cmdKey) }
    if flags.contains(.shift)   { m |= UInt32(shiftKey) }
    if flags.contains(.option)  { m |= UInt32(optionKey) }
    if flags.contains(.control) { m |= UInt32(controlKey) }
    return m
}

/// Glifos dos modificadores, na ordem convencional (⌃⌥⇧⌘).
func modifierGlyphs(_ mods: UInt32) -> String {
    var s = ""
    if mods & UInt32(controlKey) != 0 { s += "⌃" }
    if mods & UInt32(optionKey)  != 0 { s += "⌥" }
    if mods & UInt32(shiftKey)   != 0 { s += "⇧" }
    if mods & UInt32(cmdKey)     != 0 { s += "⌘" }
    return s
}

private func fourCharCode(_ s: String) -> OSType {
    var result: OSType = 0
    for ch in s.utf8.prefix(4) { result = (result << 8) + OSType(ch) }
    return result
}
