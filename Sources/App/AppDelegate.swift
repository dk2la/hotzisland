import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let services = ModuleServices()
    private var statusItem: NSStatusItem?
    private var notchController: NotchWindowController?
    private var widgetController: WidgetWindowController?
    private var settingsWindow: SettingsWindowController?
    private let onboarding = OnboardingWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        notchController = NotchWindowController(
            settings: settings,
            services: services,
            playbooks: services.playbookStore
        )

        // The widget window lives only in widget mode; the notch window
        // always exists (live events stay on the notch in both modes).
        settings.onDisplayModeChange = { [weak self] mode in
            self?.applyDisplayMode(mode)
        }
        settings.addChangeHandler { [weak self] in
            self?.widgetController?.settingsDidChange()
        }
        applyDisplayMode(settings.displayMode)

        // Island UI (e.g. the "+ new" playbook card) asks for the settings
        // window through this notification.
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

    private func applyDisplayMode(_ mode: DisplayMode) {
        switch mode {
        case .island:
            widgetController?.tearDown()
            widgetController = nil
        case .widget:
            guard widgetController == nil else { return }
            widgetController = WidgetWindowController(
                settings: settings,
                services: services,
                playbooks: services.playbookStore
            )
        }
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
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                settings: settings,
                playbooks: services.playbookStore,
                services: services
            )
        }
        settingsWindow?.show(page: page)
    }
}
