import AppKit
import OSLog
import SwiftUI

/// Owns the island panel: positions it on the notch, resizes the window in
/// step with the state machine, and survives display configuration changes.
/// Resting, the island shows live events and compact indicators; expanded,
/// it hosts the app's settings (click the notch, ⌃⌥M, or the menu bar).
@MainActor
final class NotchWindowController: NSObject {
    private let panel = NotchPanel()
    private let viewModel = NotchViewModel()
    private var closedSize: CGSize = NotchMetrics.fallbackClosedSize
    /// Target state — the controller's source of truth. May be one tick
    /// ahead of viewModel.state (see requestState).
    private var targetState: NotchState = .closed
    private var collapseTask: Task<Void, Never>?
    private var expandTask: Task<Void, Never>?
    private var eventShowTask: Task<Void, Never>?
    private var eventDismissTask: Task<Void, Never>?
    /// Set synchronously in `present` — guards the window frame against
    /// idle-state churn during the one tick before `activeEvent` lands and
    /// for as long as the event is on screen.
    private var eventOwnsWindow = false
    private var clickMonitors: [Any] = []
    private let services: ModuleServices
    private let settings: AppSettings
    private let playbookStore: PlaybookStore
    private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "window")

    init(settings: AppSettings, services: ModuleServices, playbooks: PlaybookStore) {
        self.settings = settings
        self.services = services
        self.playbookStore = playbooks
        super.init()

        services.playbookRunner.onFinished = { [weak self] playbook, _ in
            self?.present(.playbookRan(name: playbook.name))
        }

        settings.addChangeHandler { [weak self] in
            guard let self else { return }
            self.refreshIdleState()
            // Live window resize while the user drags the panel grip.
            if self.targetState == .expanded, let screen = NotchGeometry.targetScreen {
                self.collapseTask?.cancel()
                self.panel.setFrame(self.frame(for: .expanded, on: screen), display: true)
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        attachToScreen()
        setUpLiveEvents()
        viewModel.onIslandTapped = { [weak self] in
            self?.openSettings(page: nil)
        }
        viewModel.onClose = { [weak self] in
            self?.closeSettings()
        }
    }

    // MARK: - Settings island

    /// Expands the island onto the settings, optionally on a given page.
    func openSettings(page: SettingsView.Page?) {
        if let page {
            viewModel.pageSelection.page = page
        }
        requestState(.expanded)
    }

    func closeSettings() {
        guard targetState == .expanded else { return }
        requestState(idleState)
    }

    func toggleSettings() {
        if targetState == .expanded {
            closeSettings()
        } else {
            openSettings(page: nil)
        }
    }

    /// While expanded, a click anywhere outside the island closes it — the
    /// same grammar as the widget panel. Installed on expand, removed on
    /// collapse so the monitors never outlive the panel.
    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: mask,
            handler: { [weak self] _ in
                self?.handleOutsideClick(at: NSEvent.mouseLocation)
            }
        ) {
            clickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: mask,
            handler: { [weak self] event in
                // Local events carry window coordinates; only a click in
                // another of our windows (the widget) counts as outside.
                if event.window !== self?.panel {
                    self?.handleOutsideClick(at: NSEvent.mouseLocation)
                }
                return event
            }
        ) {
            clickMonitors.append(local)
        }
    }

    private func removeOutsideClickMonitors() {
        for monitor in clickMonitors {
            NSEvent.removeMonitor(monitor)
        }
        clickMonitors.removeAll()
    }

    private func handleOutsideClick(at location: NSPoint) {
        guard targetState == .expanded, !viewModel.isResizingPanel,
              let screen = NotchGeometry.targetScreen else { return }
        if !frame(for: .expanded, on: screen).contains(location) {
            closeSettings()
        }
    }

    private func setUpLiveEvents() {
        let handler: (LiveEvent) -> Void = { [weak self] event in
            self?.present(event)
        }
        services.powerMonitor.onEvent = handler
        services.audioMonitor.onEvent = handler
        services.mediaCenter.onPlaybackChanged = { [weak self] in
            self?.refreshIdleState()
        }
        services.timerService.onRunningChanged = { [weak self] in
            self?.refreshIdleState()
        }
        services.timerService.onFinished = { [weak self] in
            self?.present(.timerFinished)
        }
    }

    /// The island's resting state: compact while a timer runs or something
    /// is playing, fully closed otherwise. "Invisible" idle mode always
    /// closes fully.
    private var idleState: NotchState {
        guard settings.idleMode == .compact else { return .closed }
        if services.timerService.isRunning || services.mediaCenter.track?.isPlaying == true {
            return .compact
        }
        return .closed
    }

    private func refreshIdleState() {
        guard targetState != .expanded else { return }
        // A live event owns the window frame — the dismiss task restores
        // the idle state itself.
        guard !eventOwnsWindow else { return }
        requestState(idleState)
    }

    /// Shows a transient live event on the closed island. Repeated events
    /// (e.g. a volume sweep) update the content in place and restart the
    /// dismiss timer.
    func present(_ event: LiveEvent) {
        guard targetState != .expanded,
              let screen = NotchGeometry.targetScreen else { return }
        log.info("event \(String(describing: event), privacy: .public)")
        collapseTask?.cancel()
        eventShowTask?.cancel()
        eventDismissTask?.cancel()

        // The flag goes up synchronously: callbacks that fire right after
        // (e.g. the timer's onRunningChanged) must not reshape the window
        // during the tick before `activeEvent` lands.
        eventOwnsWindow = true

        // Same two-step as expansion: size the window silently first, run the
        // grow animation on the next tick in a stable coordinate space — the
        // bulge then grows symmetrically out of the notch.
        panel.setFrame(eventFrame(on: screen), display: true)
        eventShowTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            self?.viewModel.activeEvent = event
        }

        eventDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(NotchMetrics.eventDisplayMilliseconds))
            guard !Task.isCancelled, let self else { return }
            self.viewModel.activeEvent = nil
            try? await Task.sleep(for: .milliseconds(NotchMetrics.windowCollapseDelayMilliseconds))
            guard !Task.isCancelled, let screen = NotchGeometry.targetScreen else { return }
            self.eventOwnsWindow = false
            guard self.targetState != .expanded else { return }
            // Settle into the current idle state — the state machine was
            // frozen while the event was on screen.
            let idle = self.idleState
            self.targetState = idle
            self.viewModel.setState(idle)
            self.panel.setFrame(self.frame(for: idle, on: screen), display: true)
        }
    }

    private func eventFrame(on screen: NSScreen) -> NSRect {
        let size = CGSize(
            width: closedSize.width + NotchMetrics.eventSideWidth * 2,
            height: closedSize.height
        )
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Single entry point for state changes: prepare the window frame first,
    /// then run the animation.
    private func requestState(_ newState: NotchState) {
        guard newState != targetState else { return }
        log.info("state -> \(String(describing: newState), privacy: .public) mouse=\(NSStringFromPoint(NSEvent.mouseLocation), privacy: .public)")
        targetState = newState
        collapseTask?.cancel()
        expandTask?.cancel()
        guard let screen = NotchGeometry.targetScreen else { return }

        switch newState {
        case .expanded:
            // Expansion takes over: a visible live event is dismissed.
            eventShowTask?.cancel()
            eventDismissTask?.cancel()
            eventOwnsWindow = false
            viewModel.activeEvent = nil
            // Settings host text input — let the panel take key status
            // without activating the app.
            panel.allowsKeyFocus = true
            installOutsideClickMonitors()
            // Grow the window silently first: the island is pinned to the top
            // center and does not visually move. The animation starts on the
            // next tick, once the window's coordinate space is stable —
            // otherwise the growth starts from shifted coordinates and looks
            // like a widget sliding onto the notch from the side.
            panel.setFrame(frame(for: .expanded, on: screen), display: true)
            expandTask = Task { [weak self] in
                guard !Task.isCancelled else { return }
                self?.viewModel.setState(.expanded)
            }
        case .closed, .compact:
            removeOutsideClickMonitors()
            panel.allowsKeyFocus = false
            if panel.isKeyWindow {
                panel.resignKey()
            }
            // While a live event is on screen it owns the window frame; only
            // the logical state advances — the dismiss task settles the rest.
            guard !eventOwnsWindow else {
                viewModel.setState(newState)
                return
            }
            let target = frame(for: newState, on: screen)
            if target.width > panel.frame.width {
                // Growing (closed → compact): widen the window silently
                // first, animate on the next tick in a stable coordinate
                // space — mirrors the expansion two-step.
                panel.setFrame(target, display: true)
                expandTask = Task { [weak self] in
                    guard !Task.isCancelled else { return }
                    self?.viewModel.setState(newState)
                }
            } else {
                viewModel.setState(newState)
                // Shrink the window only after SwiftUI has finished the close
                // animation, otherwise it would clip the capsule mid-flight.
                collapseTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(NotchMetrics.windowCollapseDelayMilliseconds))
                    guard !Task.isCancelled, let self,
                          let screen = NotchGeometry.targetScreen else { return }
                    self.panel.setFrame(self.frame(for: newState, on: screen), display: true)
                }
            }
        }
    }

    private func attachToScreen() {
        guard let screen = NotchGeometry.targetScreen else { return }
        closedSize = NotchGeometry.closedSize(on: screen)

        let rootView = NotchRootView(
            viewModel: viewModel,
            services: services,
            settings: settings,
            playbooks: playbookStore,
            closedSize: closedSize
        )
        let hostingView = NotchHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView

        panel.setFrame(frame(for: viewModel.state, on: screen), display: true)
        panel.orderFrontRegardless()
    }

    private func frame(for state: NotchState, on screen: NSScreen) -> NSRect {
        let size: CGSize = switch state {
        case .expanded:
            // Already clamped (including to the screen) by AppSettings — the
            // window and the SwiftUI island must always agree on this size.
            settings.expandedPanelSize
        case .compact:
            CGSize(
                width: closedSize.width + NotchMetrics.compactSideWidth * 2,
                height: closedSize.height
            )
        case .closed:
            closedSize
        }
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    @objc private func screenParametersDidChange() {
        // The island rebuilds from scratch on the (possibly new) screen, so
        // every in-flight transition and the live-event ownership must go
        // with it — otherwise `targetState` would still say "expanded" for a
        // window that is now closed, and hover could never reopen it.
        collapseTask?.cancel()
        expandTask?.cancel()
        eventShowTask?.cancel()
        eventDismissTask?.cancel()
        eventOwnsWindow = false
        viewModel.activeEvent = nil
        removeOutsideClickMonitors()
        panel.allowsKeyFocus = false
        targetState = .closed
        viewModel.setState(.closed)
        settings.revalidatePanelSize()
        attachToScreen()
    }
}
