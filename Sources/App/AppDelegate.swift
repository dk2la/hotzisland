import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let services = ModuleServices()
    private var statusItem: NSStatusItem?
    private var capsuleController: CapsuleWindowController?
    private var widgetController: WidgetWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        registerHotkeys()
        capsuleController = CapsuleWindowController(settings: settings, services: services)

        // Modules live in the edge widget; the capsule shows live
        // events and, when opened, the settings.
        widgetController = WidgetWindowController(settings: settings, services: services)
        settings.addChangeHandler { [weak self] in
            self?.widgetController?.settingsDidChange()
        }

        // Widget UI (e.g. the "+ new" playbook card) asks for the settings
        // capsule through this notification.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSettings(_:)),
            name: .pocketOpenSettings,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openOnboarding),
            name: .pocketOpenOnboarding,
            object: nil
        )

        // A demo event is asked for from the settings capsule, which sits
        // where the event would show — close it first, then flash the event.
        services.demo.presentEvent = { [weak self] event in
            guard let capsule = self?.capsuleController else { return }
            capsule.closeSettings()
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                capsule.present(event)
            }
        }

        // `--demo`: scripted data in every module from the first frame.
        if CommandLine.arguments.contains("--demo") {
            services.demo.activate()
        }

        // Developer convenience: `open Pocket.app --args --settings`
        // wins over the tour; `--onboarding` forces the tour even when the
        // user switched it off.
        if CommandLine.arguments.contains("--settings") {
            services.beginProtectedAccess()
            showSettings(page: nil)
        } else if settings.showOnboardingAtLaunch || CommandLine.arguments.contains("--onboarding") {
            deferProtectedAccessUntilTourCloses()
            // A beat after launch, so the capsule visibly drops open instead
            // of appearing already expanded.
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                self?.capsuleController?.openOnboarding()
            }
        } else {
            services.beginProtectedAccess()
        }
    }

    /// First launch: no access prompt may pile up on top of the tour. Its
    /// pages ask for the calendar and the notes folder one by one; the rest
    /// (clipboard, music players) starts once the capsule closes.
    private func deferProtectedAccessUntilTourCloses() {
        guard !settings.onboardingCompleted else {
            services.beginProtectedAccess()
            return
        }
        capsuleController?.onCollapse = { [weak self] in
            guard let self else { return }
            self.capsuleController?.onCollapse = nil
            self.settings.onboardingCompleted = true
            self.services.beginProtectedAccess()
        }
    }

    /// Global shortcuts (Carbon — no permissions needed). H and P act on
    /// the widget; M opens or closes the settings capsule.
    private func registerHotkeys() {
        let hotkeys = services.hotkeys
        hotkeys.register(.toggleWidgetHidden) { [weak self] in
            // The controller reconciles through settingsDidChange, so the
            // hotkey works even while the widget window is being rebuilt.
            self?.settings.widgetMinimized.toggle()
        }
        hotkeys.register(.togglePanelPin) { [weak self] in
            self?.settings.closeOnOutsideClick.toggle()
        }
        hotkeys.register(.toggleSettings) { [weak self] in
            self?.capsuleController?.toggleSettings()
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "capsule.portrait.fill",
            accessibilityDescription: "Pocket"
        )

        let menu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        let tourItem = NSMenuItem(
            title: "Welcome Tour…",
            action: #selector(openOnboarding),
            keyEquivalent: ""
        )
        tourItem.target = self
        menu.addItem(tourItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit Pocket",
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

    @objc private func openOnboarding() {
        capsuleController?.openOnboarding()
    }

    @objc private func handleOpenSettings(_ notification: Notification) {
        let page = (notification.userInfo?["page"] as? String)
            .flatMap(SettingsView.Page.init(rawValue:))
        showSettings(page: page)
    }

    private func showSettings(page: SettingsView.Page?) {
        capsuleController?.openSettings(page: page)
    }
}
