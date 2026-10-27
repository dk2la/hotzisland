import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let services = ModuleServices()
    private var statusItem: NSStatusItem?
    private var notchController: NotchWindowController?
    private var widgetController: WidgetWindowController?
    private let hotkeys = HotkeyService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        registerHotkeys()
        notchController = NotchWindowController(settings: settings, services: services)

        // Modules live in the edge widget; the notch island shows live
        // events and, when opened, the settings.
        widgetController = WidgetWindowController(settings: settings, services: services)
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openOnboarding),
            name: .hotzOpenOnboarding,
            object: nil
        )

        // A demo event is asked for from the settings island, which sits
        // where the event would show — close it first, then flash the event.
        services.demo.presentEvent = { [weak self] event in
            guard let notch = self?.notchController else { return }
            notch.closeSettings()
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                notch.present(event)
            }
        }

        // `--demo`: scripted data in every module from the first frame.
        if CommandLine.arguments.contains("--demo") {
            services.demo.activate()
        }

        // Developer convenience: `open HotzIsland.app --args --settings`
        // wins over the tour; `--onboarding` forces the tour even when the
        // user switched it off.
        if CommandLine.arguments.contains("--settings") {
            showSettings(page: nil)
        } else if settings.showOnboardingAtLaunch || CommandLine.arguments.contains("--onboarding") {
            // A beat after launch, so the island visibly drops open instead
            // of appearing already expanded.
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                self?.notchController?.openOnboarding()
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

    @objc private func openOnboarding() {
        notchController?.openOnboarding()
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
