import Foundation

/// One key press as an app's menu reports it, or as the user recorded it.
/// Menus usually name the key ("N", "↩", "F5"); recorded shortcuts and a few
/// Carbon-era menus only give a key code, which is translated through the
/// current layout at display time.
struct KeyStroke: Codable, Hashable, Sendable {
    /// Carbon modifier mask, the same as `KeyCombo`'s.
    var modifiers: UInt32
    var label: String?
    var keyCode: UInt32?

    /// Key caps in the system's order: ⌃ ⌥ ⇧ ⌘, then the key.
    @MainActor var keyCaps: [String] {
        // KeyCombo already knows the modifier order and the layout lookup;
        // a named key just replaces the looked-up one.
        var caps = KeyCombo(keyCode: keyCode ?? 0, modifiers: modifiers).keyCaps
        if let label {
            caps[caps.count - 1] = label
        }
        return caps
    }
}

/// A shortcut of one app: read from its menu bar, or added by the user.
struct AppShortcut: Codable, Hashable, Identifiable, Sendable {
    /// Menu path joined ("File › Export › Movie…") for menu items, so pins
    /// and tags survive a re-read; "preset:<action>" for an app's key preset,
    /// the same for the built-in set and an imported one; "custom:<uuid>"
    /// for the user's own.
    let id: String
    var title: String
    /// Menus above the item, outermost first; empty for the user's own.
    var menuPath: [String]
    var keys: KeyStroke

    var isCustom: Bool { id.hasPrefix(Self.customPrefix) }

    static let customPrefix = "custom:"
    static let presetPrefix = "preset:"
    static let pathSeparator = " › "

    static func menuItem(title: String, path: [String], keys: KeyStroke) -> AppShortcut {
        AppShortcut(id: (path + [title]).joined(separator: pathSeparator), title: title, menuPath: path, keys: keys)
    }

    static func custom(title: String, keys: KeyStroke) -> AppShortcut {
        AppShortcut(id: customPrefix + UUID().uuidString, title: title, menuPath: [], keys: keys)
    }
}

/// What the user keeps for one app: pins, tags and their own shortcuts.
struct AppShortcutPrefs: Codable, Sendable {
    var pinned: [String] = []
    /// Shortcut id → tags, for searching by words the menu does not use.
    var tags: [String: [String]] = [:]
    var custom: [AppShortcut] = []
    /// The app's key preset as imported from a file; nil: the built-in set.
    var imported: [AppShortcut]?

    var isEmpty: Bool { pinned.isEmpty && tags.isEmpty && custom.isEmpty && imported == nil }
}

/// The last read of an app's menu bar. Thrown away when the app's version
/// changes, so an update with new menus is read again.
struct MenuSnapshot: Codable, Sendable {
    var appVersion: String
    var readAt: Date
    var shortcuts: [AppShortcut]
}
