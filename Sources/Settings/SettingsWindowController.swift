import AppKit
import SwiftUI

/// A plain settings window owned by the app delegate. The SwiftUI `Settings`
/// scene is unreliable for LSUIElement agents, so the window is managed
/// manually.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow
    private let pageSelection = SettingsPageSelection()

    init(settings: AppSettings, playbooks: PlaybookStore, services: ModuleServices) {
        let hosting = NSHostingController(
            rootView: SettingsView(
                settings: settings,
                playbooks: playbooks,
                services: services,
                pageSelection: pageSelection
            )
        )
        window = NSWindow(contentViewController: hosting)
        window.title = "HotzIsland Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show(page: SettingsView.Page? = nil) {
        if let page {
            pageSelection.page = page
        }
        window.makeKeyAndOrderFront(nil)
        // An LSUIElement agent is refused cooperative activation on modern
        // macOS — without the forced variant, keystrokes keep going to the
        // previously active app and text fields appear dead.
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Shared page selection so module UI can deep-link into a settings page
/// (e.g. "Set up account" → Accounts).
@MainActor
@Observable
final class SettingsPageSelection {
    var page: SettingsView.Page = .general
}
