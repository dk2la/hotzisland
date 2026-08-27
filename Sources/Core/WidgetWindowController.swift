import AppKit
import OSLog
import SwiftUI

/// Owns the edge-docked widget window (widget display mode). Click-driven:
/// unlike the notch it registers no mouse monitors and never touches
/// NotchWindowControllerRegistry — that slot belongs to the notch.
@MainActor
final class WidgetWindowController: NSObject {
    private let panel = NotchPanel()
    private let viewModel = WidgetViewModel()
    private let settings: AppSettings
    private let services: ModuleServices
    private let playbookStore: PlaybookStore
    private var collapseTask: Task<Void, Never>?
    private var openTask: Task<Void, Never>?
    private var dragStartMouse: CGPoint?
    private var dragStartOrigin: CGPoint?
    private var isDragging = false
    /// Mouse monitors active only while the panel is open and the
    /// close-on-outside-click setting is on.
    private var outsideClickMonitors: [Any] = []
    /// Set while a minimize/restore is mid-flight: the settings write it
    /// makes would otherwise bounce back through settingsDidChange and
    /// stomp the running animation.
    private var isTogglingMinimize = false
    /// Screen the widget currently lives on. Reset to the island's target
    /// screen on display changes; updated when a drag ends elsewhere.
    private var screen: NSScreen?
    private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "widget")

    init(settings: AppSettings, services: ModuleServices, playbooks: PlaybookStore) {
        self.settings = settings
        self.services = services
        self.playbookStore = playbooks
        super.init()

        viewModel.onTabTapped = { [weak self] tab in self?.toggleTab(tab) }
        viewModel.onClose = { [weak self] in self?.closePanel() }
        viewModel.onRestore = { [weak self] in self?.setMinimized(false) }
        viewModel.onDragChanged = { [weak self] in self?.dragChanged() }
        viewModel.onDragEnded = { [weak self] in self?.dragEnded() }
        viewModel.isMinimized = settings.widgetMinimized

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        attach()
    }

    func tearDown() {
        openTask?.cancel()
        collapseTask?.cancel()
        removeOutsideClickMonitors()
        NotificationCenter.default.removeObserver(self)
        panel.orderOut(nil)
        log.info("torn down")
    }

    // MARK: - Minimize (⌃⌥H)

    func toggleMinimized() {
        setMinimized(!viewModel.isMinimized)
    }

    /// Rolls the strip up into its first button (or back down). The window
    /// stays at full size for the length of the animation — it is
    /// transparent, so only the strip is visible shrinking — and is resized
    /// afterwards. Animating the window frame at the same time would race
    /// the SwiftUI animation and read as a slide.
    func setMinimized(_ minimized: Bool) {
        guard !isTogglingMinimize, viewModel.isMinimized != minimized else { return }
        guard let screen = currentScreen else { return }
        isTogglingMinimize = true
        defer { isTogglingMinimize = false }

        openTask?.cancel()
        collapseTask?.cancel()
        collapseTask = nil
        removeOutsideClickMonitors()
        panel.allowsKeyFocus = false

        let full = stripFrame(minimized: false, on: screen)
        let target = stripFrame(minimized: minimized, on: screen)
        // Grow first / shrink last: the window must never be smaller than
        // the strip mid-animation or the content would be clipped.
        panel.setFrame(full, display: true)
        withAnimation(Theme.stateSpring) {
            viewModel.setSelectedTab(nil)
            viewModel.isMinimized = minimized
            viewModel.stripFrame = CGRect(origin: .zero, size: target.size)
            viewModel.panelFrame = .zero
        }
        if minimized {
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(NotchMetrics.windowCollapseDelayMilliseconds))
                guard !Task.isCancelled, let self else { return }
                self.collapseTask = nil
                self.panel.setFrame(target, display: true)
            }
        }
        settings.widgetMinimized = minimized
        log.info("minimized -> \(minimized, privacy: .public)")
    }

    private func stripFrame(minimized: Bool, on screen: NSScreen) -> NSRect {
        WidgetGeometry.stripFrame(
            edge: settings.widgetEdge,
            offset: settings.widgetOffset,
            iconCount: iconCount,
            minimized: minimized,
            on: screen
        )
    }

    // MARK: - Outside click (close-on-click-away)

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()
        guard settings.closeOnOutsideClick else { return }
        // Global = clicks in other apps; local = clicks in our own windows
        // (settings, onboarding) that are not the widget panel. Mouse
        // monitors need no permissions, unlike keyboard ones.
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePanel()
        } {
            outsideClickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            if let self, event.window !== self.panel {
                self.closePanel()
            }
            return event
        } {
            outsideClickMonitors.append(local)
        }
    }

    private func removeOutsideClickMonitors() {
        for monitor in outsideClickMonitors {
            NSEvent.removeMonitor(monitor)
        }
        outsideClickMonitors.removeAll()
    }

    /// Settings changed (tabs, panel size, placement, theme) — re-derive the
    /// layout. Frames are idempotent, so over-calling is harmless.
    func settingsDidChange() {
        // Our own minimize writes land here; the animation owns the frames.
        guard !isTogglingMinimize else { return }
        // Minimize may have been flipped by the hotkey or another surface.
        if settings.widgetMinimized != viewModel.isMinimized {
            setMinimized(settings.widgetMinimized)
            return
        }
        // The open tab may have been disabled — fall back to the first
        // enabled one (there is always at least one).
        if let tab = viewModel.selectedTab, !settings.isEnabled(tab) {
            viewModel.setSelectedTab(settings.orderedEnabledTabs.first)
        }
        // The pin toggle can change while a panel is open.
        if viewModel.selectedTab != nil {
            installOutsideClickMonitors()
        }
        guard !isDragging else { return }
        viewModel.edge = settings.widgetEdge
        if viewModel.selectedTab != nil {
            applyExpandedFrame()
        } else if collapseTask == nil {
            applyDockedFrame()
        }
    }

    // MARK: - Window lifecycle

    private func attach() {
        screen = NotchGeometry.targetScreen
        viewModel.edge = settings.widgetEdge

        let rootView = WidgetRootView(
            viewModel: viewModel,
            services: services,
            settings: settings,
            playbooks: playbookStore
        )
        let hostingView = NotchHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView

        applyDockedFrame()
        panel.orderFrontRegardless()
        log.info("attached edge=\(self.settings.widgetEdge.rawValue, privacy: .public) offset=\(self.settings.widgetOffset, privacy: .public)")
    }

    @objc private func screenParametersDidChange() {
        screen = NotchGeometry.targetScreen
        openTask?.cancel()
        collapseTask?.cancel()
        collapseTask = nil
        withInstantTransaction {
            viewModel.setSelectedTab(nil)
        }
        applyDockedFrame()
    }

    // MARK: - Panel open/close

    private func toggleTab(_ tab: NotchTab) {
        log.info("tab -> \(tab.rawValue, privacy: .public)")
        if viewModel.isMinimized {
            // The lone visible button unfolds the widget and opens itself.
            setMinimized(false)
            openPanel(tab)
            return
        }
        if viewModel.selectedTab == tab {
            closePanel()
        } else if viewModel.selectedTab != nil {
            // Window is already sized for the panel — switch in place.
            viewModel.setSelectedTab(tab)
        } else {
            openPanel(tab)
        }
    }

    private func openPanel(_ tab: NotchTab) {
        guard let screen = currentScreen, !viewModel.isMinimized else { return }
        collapseTask?.cancel()
        collapseTask = nil
        // Module panels host text input — let the panel take key status
        // without activating the app.
        panel.allowsKeyFocus = true
        // Two-phase, same as the notch: grow the window silently first (the
        // strip's local frame shifts in the same tick, so it does not move
        // on screen), animate the panel in on the next tick once the
        // window's coordinate space is stable.
        applyLayout(WidgetGeometry.expandedLayout(
            edge: settings.widgetEdge,
            offset: settings.widgetOffset,
            iconCount: iconCount,
            panelSize: settings.expandedPanelSize,
            on: screen
        ))
        openTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            self?.viewModel.setSelectedTab(tab)
        }
        installOutsideClickMonitors()
    }

    private func closePanel() {
        guard viewModel.selectedTab != nil else { return }
        removeOutsideClickMonitors()
        openTask?.cancel()
        panel.allowsKeyFocus = false
        if panel.isKeyWindow {
            panel.resignKey()
        }
        viewModel.setSelectedTab(nil)
        // Shrink the window only after the close animation has finished,
        // otherwise it would clip the panel mid-flight.
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(NotchMetrics.windowCollapseDelayMilliseconds))
            guard !Task.isCancelled, let self else { return }
            self.collapseTask = nil
            self.applyDockedFrame()
        }
    }

    // MARK: - Dragging

    private func dragChanged() {
        let now = NSEvent.mouseLocation
        guard let startMouse = dragStartMouse, let startOrigin = dragStartOrigin else {
            // Drag takes over: the panel snaps shut, the strip follows the
            // cursor. The collapsed frame equals the strip's current spot,
            // so there is no visual jump.
            openTask?.cancel()
            collapseTask?.cancel()
            collapseTask = nil
            removeOutsideClickMonitors()
            withInstantTransaction {
                viewModel.setSelectedTab(nil)
            }
            applyDockedFrame()
            dragStartMouse = now
            dragStartOrigin = panel.frame.origin
            isDragging = true
            return
        }
        panel.setFrameOrigin(CGPoint(
            x: startOrigin.x + (now.x - startMouse.x),
            y: startOrigin.y + (now.y - startMouse.y)
        ))
    }

    private func dragEnded() {
        dragStartMouse = nil
        dragStartOrigin = nil
        isDragging = false

        let mouse = NSEvent.mouseLocation
        let dropScreen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? panel.screen ?? currentScreen
        guard let dropScreen else { return }
        screen = dropScreen

        let placement = WidgetGeometry.nearestPlacement(for: panel.frame, on: dropScreen)
        log.info("snap edge=\(placement.edge.rawValue, privacy: .public) offset=\(placement.offset, privacy: .public)")
        viewModel.edge = placement.edge
        settings.setWidgetPlacement(edge: placement.edge, offset: placement.offset)
        applyDockedFrame(animated: true)
    }

    // MARK: - Frames

    private var iconCount: Int {
        max(settings.orderedEnabledTabs.count, 1)
    }

    private var currentScreen: NSScreen? {
        screen ?? NotchGeometry.targetScreen
    }

    /// The window's resting frame — the strip alone, sized for the current
    /// (possibly minimized) icon set.
    private func applyDockedFrame(animated: Bool = false) {
        guard let screen = currentScreen else { return }
        let strip = stripFrame(minimized: viewModel.isMinimized, on: screen)
        panel.setFrame(strip, display: true, animate: animated)
        // The window IS the strip here, so its local rect is the origin. Set
        // it without an implicit animation: the window frame already moved,
        // and animating the content on top of that reads as a slide.
        withInstantTransaction {
            viewModel.stripFrame = CGRect(origin: .zero, size: strip.size)
            viewModel.panelFrame = .zero
        }
    }

    private func applyExpandedFrame() {
        guard let screen = currentScreen else { return }
        applyLayout(WidgetGeometry.expandedLayout(
            edge: settings.widgetEdge,
            offset: settings.widgetOffset,
            iconCount: iconCount,
            panelSize: settings.expandedPanelSize,
            on: screen
        ))
    }

    private func applyLayout(_ layout: WidgetGeometry.ExpandedLayout) {
        panel.setFrame(layout.window, display: true)
        // Both rects are window-local and shift the instant the window grows.
        // Animating them would slide the strip across the new window — the
        // "flying in from nowhere" effect. The panel's own transition plays
        // on the next tick, when setSelectedTab lands.
        withInstantTransaction {
            viewModel.stripFrame = layout.stripLocal
            viewModel.panelFrame = layout.panelLocal
        }
    }

    /// State change with implicit animations suppressed (drag/display
    /// changes want instant collapse, not a clipped spring).
    private func withInstantTransaction(_ body: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }
}
