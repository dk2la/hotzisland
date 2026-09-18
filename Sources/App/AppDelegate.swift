import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let services = ModuleServices()
    private var statusItem: NSStatusItem?
    private var notchController: NotchWindowController?
    private var widgetController: WidgetWindowController?
    private let onboarding = OnboardingWindowController()
    private let hotkeys = HotkeyService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        registerHotkeys()
        notchController = NotchWindowController(
            settings: settings,
            services: services,
            playbooks: services.playbookStore
        )

        // Modules live in the edge widget; the notch island shows live
        // events and, when opened, the settings.
        widgetController = WidgetWindowController(
            settings: settings,
            services: services,
            playbooks: services.playbookStore
        )
        settings.addChangeHandler { [weak self] in
            self?.widgetController?.settingsDidChange()
        }

        // Widget UI (e.g. the "+ new" playbook card) asks for the settings
        // island through this notification.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSettings(_:)),
            name: .hotzOpenSettings,
            object: nil
        )

        // Developer convenience: `open HotzIsland.app --args --settings`.
        if CommandLine.arguments.contains("--settings") {
            showSettings(page: nil)
        }

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "onboarding.completed")
            || CommandLine.arguments.contains("--onboarding") {
            onboarding.show(settings: settings) {
                defaults.set(true, forKey: "onboarding.completed")
            }
        }
    }

    /// Global shortcuts (Carbon — no permissions needed). H and P act on
    /// the widget; M opens or closes the settings island.
    private func registerHotkeys() {
        hotkeys.register(.toggleWidgetHidden) { [weak self] in
            // The controller reconciles through settingsDidChange, so the
            // hotkey works even while the widget window is being rebuilt.
            self?.settings.widgetMinimized.toggle()
        }
        hotkeys.register(.togglePanelPin) { [weak self] in
            self?.settings.closeOnOutsideClick.toggle()
        }
        hotkeys.register(.toggleSettings) { [weak self] in
            self?.notchController?.toggleSettings()
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
        showSettings(page: nil)
    }

    @objc private func handleOpenSettings(_ notification: Notification) {
        let page = (notification.userInfo?["page"] as? String)
            .flatMap(SettingsView.Page.init(rawValue:))
        showSettings(page: page)
    }

    private func showSettings(page: SettingsView.Page?) {
        notchController?.openSettings(page: page)
    }
}
