import Carbon.HIToolbox
import Foundation

/// Apps that keep their shortcuts out of the menu bar's reach (DaVinci
/// Resolve handles keys itself, so its menu items carry none) but can
/// export them to a file. Each has a parser for that file and a built-in
/// copy of its default set, shown until the user imports their own.
enum KeyPreset {
    case davinciResolve

    static func forApp(_ bundleID: String) -> KeyPreset? {
        switch bundleID {
        case "com.blackmagic-design.DaVinciResolve": .davinciResolve
        default: nil
        }
    }

    /// The app's default set, bundled with Pocket.
    var builtIn: [AppShortcut] {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text) ?? []
    }

    /// nil when the text is not this app's export.
    func parse(_ text: String) -> [AppShortcut]? {
        switch self {
        case .davinciResolve: ResolveKeyPreset.parse(text)
        }
    }

    private var resourceName: String {
        switch self {
        case .davinciResolve: "DaVinciResolve"
        }
    }
}

/// DaVinci Resolve's "Export Preset" text: `# Section` headings, then
/// `actionId := Ctrl+Shift+N | Alt+N` per line. "Ctrl" means ⌘, "Alt" ⌥ and
/// "Meta" ⌃ (the file says so); the first alternative is the one Resolve
/// shows in its menus, so it is the one shown here.
enum ResolveKeyPreset {
    static func parse(_ text: String) -> [AppShortcut]? {
        var shortcuts: [AppShortcut] = []
        var seen: Set<String> = []
        var section = "Resolve"
        var bindings = 0
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                if let heading = heading(line) { section = heading }
                continue
            }
            guard let separator = line.range(of: ":=") else { continue }
            bindings += 1
            let action = line[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
            let value = line[separator.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !action.isEmpty, !value.isEmpty,
                  let first = value.components(separatedBy: " | ").first,
                  let keys = keyStroke(first.trimmingCharacters(in: .whitespaces)),
                  seen.insert(action).inserted
            else { continue }
            shortcuts.append(AppShortcut(
                id: AppShortcut.presetPrefix + action,
                title: title(of: action),
                menuPath: [section],
                keys: keys
            ))
        }
        return bindings > 0 ? shortcuts : nil
    }

    /// "# Timeline" is a heading; "# see EBNF grammar…" or the list of
    /// menus on top are remarks.
    private static func heading(_ line: String) -> String? {
        let text = line.dropFirst().trimmingCharacters(in: .whitespaces)
        let words = text.split(separator: " ")
        guard (1...3).contains(words.count),
              text.allSatisfy({ $0.isLetter || $0 == " " }) else { return nil }
        return text
    }

    /// "fileNewFolder" → "New Folder": the leading word repeats the menu.
    /// Scoped ids ("MediaPool.Context_setPosterFrame") keep every word.
    private static func title(of action: String) -> String {
        let scoped = action.contains(".")
        var name = String(action.split(separator: ".").last ?? Substring(action))
        if name.hasPrefix("Context_") { name.removeFirst("Context_".count) }
        var words = splitWords(name)
        if !scoped, words.count > 1 { words.removeFirst() }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// camelCase, ACRONYMRuns and digit runs into words.
    private static func splitWords(_ name: String) -> [String] {
        var words: [String] = []
        var current = ""
        let characters = Array(name.replacingOccurrences(of: "_", with: " "))
        for (index, character) in characters.enumerated() {
            if character == " " {
                if !current.isEmpty { words.append(current) }
                current = ""
                continue
            }
            if let previous = current.last {
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                let startsWord =
                    (character.isUppercase && previous.isLowercase)
                    || (character.isUppercase && previous.isUppercase && (next?.isLowercase ?? false))
                    || (character.isNumber != previous.isNumber)
                if startsWord {
                    words.append(current)
                    current = ""
                }
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    // MARK: - Keys

    /// "Ctrl+Shift+N", "Ctrl++", "Numpad+Enter", "Cut".
    static func keyStroke(_ text: String) -> KeyStroke? {
        if let standard = standardActions[text] { return standard }
        var parts: [String]
        if text == "+" {
            parts = ["+"]
        } else if text.hasSuffix("++") {
            parts = text.dropLast(2).split(separator: "+").map(String.init) + ["+"]
        } else {
            parts = text.split(separator: "+").map(String.init)
        }
        guard let key = parts.popLast() else { return nil }
        var mask: UInt32 = 0
        var keypad = false
        for modifier in parts {
            switch modifier {
            case "Ctrl": mask |= UInt32(cmdKey)
            case "Alt": mask |= UInt32(optionKey)
            case "Shift": mask |= UInt32(shiftKey)
            case "Meta": mask |= UInt32(controlKey)
            case "Numpad": keypad = true
            default: return nil
            }
        }
        let label = keyLabels[key] ?? key.uppercased()
        return KeyStroke(modifiers: mask, label: keypad && key != "Enter" ? "Num \(label)" : label)
    }

    /// Resolve names the system edit commands instead of their keys.
    private static let standardActions: [String: KeyStroke] = [
        "Cut": KeyStroke(modifiers: UInt32(cmdKey), label: "X"),
        "Copy": KeyStroke(modifiers: UInt32(cmdKey), label: "C"),
        "Paste": KeyStroke(modifiers: UInt32(cmdKey), label: "V"),
    ]

    private static let keyLabels: [String: String] = [
        "Left": "←", "Right": "→", "Up": "↑", "Down": "↓",
        "Home": "↖", "End": "↘", "PgUp": "⇞", "PgDown": "⇟",
        "Enter": "⌤", "Return": "↩", "Tab": "⇥", "Space": "Space",
        "Backspace": "⌫", "Del": "⌦", "Esc": "⎋", "Escape": "⎋",
    ]
}
