import ApplicationServices
import Carbon.HIToolbox

/// Reads every shortcut in another app's menu bar through the Accessibility
/// API. Each attribute read is a round trip to that app's main thread, so a
/// big menu bar (hundreds of items) costs a noticeable fraction of a second:
/// run it off the main actor, and only when nothing is cached.
///
/// One `AXUIElementCopyMultipleAttributeValues` per item keeps it to a
/// single round trip each; every element gets a short messaging timeout, and
/// the first timeout ends the whole read — a hung app must not stall us for
/// timeout × items.
struct MenuShortcutReader {
    private static let timeout: Float = 0.5
    /// Deep enough for File › Export › Format › …; deeper menus are lists
    /// of documents or presets, not commands.
    private static let maxDepth = 4
    /// Safety net for menus that list thousands of generated items.
    private static let maxItems = 4000

    private static let itemAttributes = [
        kAXTitleAttribute,
        kAXMenuItemCmdCharAttribute,
        kAXMenuItemCmdVirtualKeyAttribute,
        kAXMenuItemCmdGlyphAttribute,
        kAXMenuItemCmdModifiersAttribute,
        kAXChildrenAttribute,
    ]

    private var shortcuts: [AppShortcut] = []
    private var seen: Set<String> = []
    private var visited = 0
    private var failed = false

    /// The app's shortcuts in menu order; nil when the menu bar could not be
    /// read (no access, the app hung or quit) — not cached, tried again later.
    static func read(pid: pid_t) -> [AppShortcut]? {
        var reader = MenuShortcutReader()
        return reader.run(app: AXUIElementCreateApplication(pid))
    }

    private mutating func run(app: AXUIElement) -> [AppShortcut]? {
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &value) {
        case .success:
            break
        case .noValue, .attributeUnsupported:
            // Agents and menu-bar extras: no menu, so no shortcuts.
            return []
        default:
            return nil
        }
        guard let menuBar = value, CFGetTypeID(menuBar) == AXUIElementGetTypeID() else { return [] }
        // The first bar item is the Apple menu — the system's, not the app's.
        for barItem in children(of: menuBar as! AXUIElement).dropFirst() {
            guard let title = string(barItem, kAXTitleAttribute), !title.isEmpty else { continue }
            for menu in children(of: barItem) {
                collect(menu: menu, path: [title], depth: 1)
            }
            if failed { return nil }
        }
        return shortcuts
    }

    private mutating func collect(menu: AXUIElement, path: [String], depth: Int) {
        for item in children(of: menu) {
            guard !failed, visited < Self.maxItems else { return }
            visited += 1
            AXUIElementSetMessagingTimeout(item, Self.timeout)
            var raw: CFArray?
            let error = AXUIElementCopyMultipleAttributeValues(item, Self.itemAttributes as CFArray, AXCopyMultipleAttributeOptions(), &raw)
            guard error == .success, let values = raw as? [Any], values.count == 6 else {
                if error == .cannotComplete { failed = true }
                continue
            }
            // Separators have no title.
            guard let title = values[0] as? String, !title.isEmpty else { continue }
            if let keys = Self.keyStroke(
                character: values[1] as? String,
                virtualKey: values[2] as? Int,
                glyph: values[3] as? Int,
                modifiers: values[4] as? Int
            ) {
                let shortcut = AppShortcut.menuItem(title: title, path: path, keys: keys)
                if seen.insert(shortcut.id).inserted {
                    shortcuts.append(shortcut)
                }
            }
            if depth < Self.maxDepth, let submenus = values[5] as? [AXUIElement] {
                for submenu in submenus {
                    collect(menu: submenu, path: path + [title], depth: depth + 1)
                }
            }
        }
    }

    // MARK: - AX plumbing

    private mutating func children(of element: AXUIElement) -> [AXUIElement] {
        AXUIElementSetMessagingTimeout(element, Self.timeout)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        if error == .cannotComplete { failed = true }
        return (value as? [AXUIElement]) ?? []
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    // MARK: - Key decoding

    /// A menu names its key one of three ways: a glyph code (arrows, ⌫, F-keys),
    /// a character, or — rarely — a virtual key code. No key, no shortcut.
    static func keyStroke(character: String?, virtualKey: Int?, glyph: Int?, modifiers: Int?) -> KeyStroke? {
        let mask = carbonModifiers(modifiers ?? 0)
        if let glyph, let label = glyphLabels[glyph] {
            return KeyStroke(modifiers: mask, label: label)
        }
        if let character, let label = label(for: character) {
            return KeyStroke(modifiers: mask, label: label)
        }
        // Key code 0 is "A", but menus without a shortcut also report 0.
        if let virtualKey, virtualKey > 0 {
            return KeyStroke(modifiers: mask, keyCode: UInt32(virtualKey))
        }
        return nil
    }

    /// AX menu modifiers: ⌘ is implied unless the "no command" bit is set.
    private static func carbonModifiers(_ ax: Int) -> UInt32 {
        var mask: UInt32 = 0
        if ax & 1 << 0 != 0 { mask |= UInt32(shiftKey) }
        if ax & 1 << 1 != 0 { mask |= UInt32(optionKey) }
        if ax & 1 << 2 != 0 { mask |= UInt32(controlKey) }
        if ax & 1 << 3 == 0 { mask |= UInt32(cmdKey) }
        return mask
    }

    private static func label(for character: String) -> String? {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
            let trimmed = character.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed.uppercased()
        }
        let value = Int(scalar.value)
        if let special = characterLabels[value] { return special }
        // NSF1FunctionKey … NSF35FunctionKey.
        if (0xF704...0xF726).contains(value) { return "F\(value - 0xF704 + 1)" }
        // Other control and private-use characters have no printable face.
        if value < 0x20 || (0xF700...0xF8FF).contains(value) { return nil }
        return character.uppercased()
    }

    private static let characterLabels: [Int: String] = [
        0x03: "⌤", 0x08: "⌫", 0x09: "⇥", 0x0D: "↩", 0x1B: "⎋", 0x20: "Space", 0x7F: "⌫",
        0xF700: "↑", 0xF701: "↓", 0xF702: "←", 0xF703: "→",
        0xF728: "⌦", 0xF729: "↖", 0xF72B: "↘", 0xF72C: "⇞", 0xF72D: "⇟",
    ]

    /// Carbon menu glyph codes (HIToolbox Menus.h) that stand for a key.
    private static let glyphLabels: [Int: String] = {
        var labels: [Int: String] = [
            0x02: "⇥", 0x03: "⇤", 0x04: "⌤", 0x09: "Space", 0x0A: "⌦", 0x0B: "↩",
            0x10: "↓", 0x17: "⌫", 0x18: "←", 0x19: "↑", 0x1A: "→", 0x1B: "⎋", 0x1C: "⌧",
            0x62: "⇞", 0x63: "⇪", 0x64: "←", 0x65: "→", 0x66: "↖", 0x68: "↑",
            0x69: "↘", 0x6A: "↓", 0x6B: "⇟", 0x8C: "⏏",
        ]
        // F1–F12 are 0x6F–0x7A, F13–F15 0x87–0x89, F16–F19 0x8F–0x92.
        for n in 0..<12 { labels[0x6F + n] = "F\(n + 1)" }
        for n in 0..<3 { labels[0x87 + n] = "F\(n + 13)" }
        for n in 0..<4 { labels[0x8F + n] = "F\(n + 16)" }
        return labels
    }()
}
