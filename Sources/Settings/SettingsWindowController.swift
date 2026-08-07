import AppKit
import SwiftUI

/// A plain settings window owned by the app delegate. The SwiftUI `Settings`
/// scene is unreliable for LSUIElement agents, so the window is managed
/// manually.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(settings: AppSettings) {
        let hosting = NSHostingController(rootView: SettingsView(settings: settings))
        window = NSWindow(contentViewController: hosting)
        window.title = "HotzIsland Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
