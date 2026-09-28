import AppKit
import Carbon

@MainActor final class OverlayHotKey {
    private var reference: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var action: () -> Void
    private var identifier = EventHotKeyID(signature: OSType(0x53504C53), id: 1)
    private var keyName: String

    init(key: String, action: @escaping () -> Void) {
        self.keyName = key; self.action = action
        install()
    }
    func update(key: String) { guard key != keyName else { return }; keyName = key; uninstall(); install() }
    private func install() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let instance = Unmanaged<OverlayHotKey>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in instance.action() }
            return noErr
        }, 1, &eventType, context, &reference)
        let parts = keyName
        var modifiers: UInt32 = 0
        if parts.contains("⌃") { modifiers |= UInt32(controlKey) }
        if parts.contains("⌥") { modifiers |= UInt32(optionKey) }
        if parts.contains("⇧") { modifiers |= UInt32(shiftKey) }
        if parts.contains("⌘") { modifiers |= UInt32(cmdKey) }
        let keyCode: UInt32 = parts.uppercased().contains("P") ? UInt32(kVK_ANSI_P) : parts.uppercased().contains("H") ? UInt32(kVK_ANSI_H) : UInt32(kVK_ANSI_O)
        RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
    private func uninstall() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
        if let reference { RemoveEventHandler(reference); self.reference = nil }
    }
    deinit { if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }; if let reference { RemoveEventHandler(reference) } }
}
