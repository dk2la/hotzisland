import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let services = ModuleServices()
    private var statusItem: NSStatusItem?
    private var displayModeMenuItem: NSMenuItem?
    private var notchController: NotchWindowController?
    private var widgetController: WidgetWindowController?
    private var settingsWindow: SettingsWindowController?
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

    /// Global shortcuts (Carbon — no permissions needed). H and P act on
    /// the widget surface and are inert in island mode by design; M flips
    /// between the surfaces from anywhere.
    private func registerHotkeys() {
        hotkeys.register(.toggleWidgetHidden) { [weak self] in
            guard let self, self.settings.displayMode == .widget else { return }
            // The controller reconciles through settingsDidChange, so the
            // hotkey works even while the widget window is being rebuilt.
            self.settings.widgetMinimized.toggle()
        }
        hotkeys.register(.togglePanelPin) { [weak self] in
            self?.settings.closeOnOutsideClick.toggle()
        }
        hotkeys.register(.toggleDisplayMode) { [weak self] in
            self?.settings.toggleDisplayMode()
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "capsule.portrait.fill",
            accessibilityDescription: "HotzIsland"
        )

        let menu = NSMenu()
        menu.delegate = self
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        // Title is stamped in menuNeedsUpdate — it names the mode the click
        // switches TO, so it must reflect the current mode at open time.
        let modeItem = NSMenuItem(
            title: "",
            action: #selector(toggleDisplayModeAction),
            keyEquivalent: ""
        )
        modeItem.target = self
        menu.addItem(modeItem)
        displayModeMenuItem = modeItem
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

    @objc private func toggleDisplayModeAction() {
        settings.toggleDisplayMode()
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

extension AppDelegate: NSMenuDelegate {
    /// AppKit opens menus on the main thread; the protocol requirement is
    /// nonisolated, hence the assumption.
    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            displayModeMenuItem?.title = L10n.t(
                settings.displayMode == .widget ? .menuIslandMode : .menuWidgetMode
            )
        }
    }
}
