import AppKit
import Carbon.HIToolbox

/// A global shortcut: one physical key plus Carbon modifiers. Stored by key
/// code, so it means the same key whatever the input layout — and shown
/// through the ASCII-capable layout, so ⌃⌥H reads "H" while typing Russian.
struct KeyCombo: Equatable, Sendable {
    var keyCode: UInt32
    /// Carbon modifier mask (controlKey | optionKey | shiftKey | cmdKey).
    var modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// The combination of a key press; nil for a bare modifier.
    init?(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        guard !Self.modifierKeyCodes.contains(Int(keyCode)) else { return nil }
        var mask: UInt32 = 0
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        self.init(keyCode: UInt32(keyCode), modifiers: mask)
    }

    /// A global shortcut must not swallow typing: it needs ⌃, ⌥ or ⌘ —
    /// only the function keys may stand alone.
    var isAcceptable: Bool {
        let strong = UInt32(controlKey | optionKey | cmdKey)
        return modifiers & strong != 0 || Self.functionKeys[Int(keyCode)] != nil
    }

    /// Key caps in the system's order: ⌃ ⌥ ⇧ ⌘, then the key.
    @MainActor var keyCaps: [String] {
        var caps: [String] = []
        if modifiers & UInt32(controlKey) != 0 { caps.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { caps.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { caps.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { caps.append("⌘") }
        caps.append(keyLabel)
        return caps
    }

    @MainActor private var keyLabel: String {
        if let special = Self.specialKeys[Int(keyCode)] ?? Self.functionKeys[Int(keyCode)] {
            return special
        }
        return Self.layoutCharacter(for: keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    // MARK: - Persistence

    var storedValue: [String: Int] {
        ["key": Int(keyCode), "mods": Int(modifiers)]
    }

    init?(storedValue: Any?) {
        guard let dict = storedValue as? [String: Int],
              let key = dict["key"], let mods = dict["mods"] else { return nil }
        self.init(keyCode: UInt32(key), modifiers: UInt32(mods))
    }

    // MARK: - Key names

    /// What the key types on the current ASCII-capable layout.
    @MainActor private static func layoutCharacter(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        return bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
            guard status == noErr, length > 0 else { return nil }
            let text = String(utf16CodeUnits: chars, count: length)
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        }
    }

    private static let modifierKeyCodes: Set<Int> = [
        kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift,
        kVK_Option, kVK_RightOption, kVK_Control, kVK_RightControl,
        kVK_CapsLock, kVK_Function,
    ]

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
        kVK_Escape: "⎋", kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←",
        kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_ANSI_KeypadEnter: "⌤",
    ]

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14",
        kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]
}
