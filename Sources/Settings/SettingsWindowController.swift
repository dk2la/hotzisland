import AppKit
import SwiftUI

/// A plain settings window owned by the app delegate. The SwiftUI `Settings`
/// scene is unreliable for LSUIElement agents, so the window is managed
/// manually.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(settings: AppSettings, playbooks: PlaybookStore) {
        let hosting = NSHostingController(
            rootView: SettingsView(settings: settings, playbooks: playbooks)
        )
        window = NSWindow(contentViewController: hosting)
        window.title = "HotzIsland Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        // An LSUIElement agent is refused cooperative activation on modern
        // macOS — without the forced variant, keystrokes keep going to the
        // previously active app and text fields appear dead.
        NSApp.activate(ignoringOtherApps: true)
    }
}
