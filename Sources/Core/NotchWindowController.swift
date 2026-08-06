import AppKit
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

    override init() {
        super.init()

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
    }

    /// The island's resting state: compact while something is playing,
    /// fully closed otherwise.
    private var idleState: NotchState {
        mediaCenter.track?.isPlaying == true ? .compact : .closed
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
            closedSize: closedSize
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView

        panel.setFrame(frame(for: viewModel.state, on: screen), display: true)
        panel.orderFrontRegardless()
    }

    private func frame(for state: NotchState, on screen: NSScreen) -> NSRect {
        let size: CGSize = switch state {
        case .expanded:
            NotchMetrics.expandedSize
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
        attachToScreen()
    }
}

/// Bridge between non-isolated NSEvent monitor callbacks and the MainActor controller.
@MainActor
enum NotchWindowControllerRegistry {
    static weak var shared: NotchWindowController?
}
