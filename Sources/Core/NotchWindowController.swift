import AppKit
import OSLog
import SwiftUI

/// Owns the island panel: positions it on the notch, resizes the window in
/// step with the state machine, and survives display configuration changes.
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
    private var mouseMonitors: [Any] = []
    private let powerMonitor = PowerSourceMonitor()
    private let audioMonitor = AudioSystemMonitor()
    private let mediaCenter = MediaCenter()
    private let calendarService = CalendarService()
    private let statsService = SystemStatsService()
    private let shelfStore = ShelfStore()
    private let clipboardStore = ClipboardStore()
    private let timerService = TimerService()
    private let settings: AppSettings
    private let playbookStore: PlaybookStore
    private let playbookRunner: PlaybookRunner
    private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "window")

    init(settings: AppSettings, playbooks: PlaybookStore) {
        self.settings = settings
        self.playbookStore = playbooks
        self.playbookRunner = PlaybookRunner(timer: timerService)
        super.init()

        playbookRunner.onFinished = { [weak self] playbook, _ in
            self?.present(.playbookRan(name: playbook.name))
        }

        settings.onChange = { [weak self] in
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
        setUpMouseTracking()
        setUpLiveEvents()
    }

    private func setUpLiveEvents() {
        let handler: (LiveEvent) -> Void = { [weak self] event in
            self?.present(event)
        }
        powerMonitor.onEvent = handler
        audioMonitor.onEvent = handler
        mediaCenter.onPlaybackChanged = { [weak self] in
            self?.refreshIdleState()
        }
        viewModel.onTabChange = { [weak self] tab in
            self?.log.info("tab -> \(tab.rawValue, privacy: .public)")
        }
        timerService.onRunningChanged = { [weak self] in
            self?.refreshIdleState()
        }
        timerService.onFinished = { [weak self] in
            self?.present(.timerFinished)
        }
        // A file dragged over the island opens the shelf to receive it.
        viewModel.onDragTargeted = { [weak self] in
            guard let self, self.targetState != .expanded else { return }
            self.viewModel.selectTab(.shelf)
            self.requestState(.expanded)
        }
    }

    /// The island's resting state: compact while a timer runs or something
    /// is playing, fully closed otherwise. "Invisible" idle mode always
    /// closes fully.
    private var idleState: NotchState {
        guard settings.idleMode == .compact else { return .closed }
        if timerService.isRunning || mediaCenter.track?.isPlaying == true {
            return .compact
        }
        return .closed
    }

    private func refreshIdleState() {
        guard targetState != .expanded else { return }
        requestState(idleState)
    }

    /// Shows a transient live event on the closed island. Repeated events
    /// (e.g. a volume sweep) update the content in place and restart the
    /// dismiss timer.
    func present(_ event: LiveEvent) {
        guard targetState != .expanded,
              let screen = NotchGeometry.targetScreen else { return }
        collapseTask?.cancel()
        eventShowTask?.cancel()
        eventDismissTask?.cancel()

        // Same two-step as expansion: size the window silently first, run the
        // grow animation on the next tick in a stable coordinate space.
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
            guard !Task.isCancelled, self.targetState != .expanded,
                  let screen = NotchGeometry.targetScreen else { return }
            self.panel.setFrame(self.frame(for: self.idleState, on: screen), display: true)
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

    /// SwiftUI `.onHover` does not fire in a non-activating agent app, so
    /// hover is computed manually from the global cursor position.
    private func setUpMouseTracking() {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { _ in
            MainActor.assumeIsolated {
                NotchWindowControllerRegistry.shared?.updateHover()
            }
        }) {
            mouseMonitors.append(global)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            MainActor.assumeIsolated {
                NotchWindowControllerRegistry.shared?.updateHover()
            }
            return event
        }
        if let local {
            mouseMonitors.append(local)
        }
        NotchWindowControllerRegistry.shared = self
    }

    private func updateHover() {
        // Dragging the resize grip may momentarily put the cursor outside
        // the shrinking panel — never collapse mid-resize.
        if viewModel.isResizingPanel, targetState == .expanded { return }
        guard let screen = NotchGeometry.targetScreen else { return }
        let location = NSEvent.mouseLocation
        let hoverZone: NSRect = if targetState == .expanded {
            frame(for: .expanded, on: screen)
        } else if viewModel.activeEvent != nil {
            eventFrame(on: screen)
        } else {
            frame(for: targetState, on: screen)
        }
        requestState(hoverZone.contains(location) ? .expanded : idleState)
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
            viewModel.activeEvent = nil
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
            viewModel.setState(newState)
            // Shrink the window only after SwiftUI has finished the close
            // animation, otherwise the window would clip the capsule mid-flight.
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(NotchMetrics.windowCollapseDelayMilliseconds))
                guard !Task.isCancelled, let self,
                      let screen = NotchGeometry.targetScreen else { return }
                self.panel.setFrame(self.frame(for: newState, on: screen), display: true)
            }
        }
    }

    private func attachToScreen() {
        guard let screen = NotchGeometry.targetScreen else { return }
        closedSize = NotchGeometry.closedSize(on: screen)

        let rootView = NotchRootView(
            viewModel: viewModel,
            power: powerMonitor,
            audio: audioMonitor,
            media: mediaCenter,
            calendar: calendarService,
            stats: statsService,
            shelf: shelfStore,
            clipboard: clipboardStore,
            timer: timerService,
            settings: settings,
            playbooks: playbookStore,
            playbookRunner: playbookRunner,
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
        viewModel.setState(.closed)
        settings.revalidatePanelSize()
        attachToScreen()
    }
}

/// Bridge between non-isolated NSEvent monitor callbacks and the MainActor controller.
@MainActor
enum NotchWindowControllerRegistry {
    static weak var shared: NotchWindowController?
}
