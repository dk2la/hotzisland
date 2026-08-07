import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private var statusItem: NSStatusItem?
    private var notchController: NotchWindowController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        notchController = NotchWindowController(settings: settings)

        // Developer convenience: `open HotzIsland.app --args --settings`.
        if CommandLine.arguments.contains("--settings") {
            openSettings()
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "capsule.portrait.fill",
            accessibilityDescription: "HotzIsland"
        )

        let menu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit HotzIsland",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        item.menu = menu

        statusItem = item
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings)
        }
        settingsWindow?.show()
    }
}
