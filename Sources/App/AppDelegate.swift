import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let playbookStore = PlaybookStore()
    private var statusItem: NSStatusItem?
    private var notchController: NotchWindowController?
    private var settingsWindow: SettingsWindowController?
    private let onboarding = OnboardingWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        notchController = NotchWindowController(settings: settings, playbooks: playbookStore)

        // Island UI (e.g. the "+ new" playbook card) asks for the settings
        // window through this notification.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: .hotzOpenSettings,
            object: nil
        )

        // Developer convenience: `open HotzIsland.app --args --settings`.
        if CommandLine.arguments.contains("--settings") {
            openSettings()
        }

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "onboarding.completed")
            || CommandLine.arguments.contains("--onboarding") {
            onboarding.show(settings: settings) {
                defaults.set(true, forKey: "onboarding.completed")
            }
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
            settingsWindow = SettingsWindowController(settings: settings, playbooks: playbookStore)
        }
        settingsWindow?.show()
    }
}
