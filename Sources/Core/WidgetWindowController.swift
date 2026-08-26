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
        viewModel.onDragChanged = { [weak self] in self?.dragChanged() }
        viewModel.onDragEnded = { [weak self] in self?.dragEnded() }

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
        NotificationCenter.default.removeObserver(self)
        panel.orderOut(nil)
        log.info("torn down")
    }

    /// Settings changed (tabs, panel size, placement, theme) — re-derive the
    /// layout. Frames are idempotent, so over-calling is harmless.
    func settingsDidChange() {
        // The open tab may have been disabled — fall back to the first
        // enabled one (there is always at least one).
        if let tab = viewModel.selectedTab, !settings.isEnabled(tab) {
            viewModel.setSelectedTab(settings.orderedEnabledTabs.first)
        }
        guard !isDragging else { return }
        viewModel.edge = settings.widgetEdge
        if viewModel.selectedTab != nil {
            applyExpandedFrame()
        } else if collapseTask == nil {
            applyCollapsedFrame()
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

        applyCollapsedFrame()
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
        applyCollapsedFrame()
    }

    // MARK: - Panel open/close

    private func toggleTab(_ tab: NotchTab) {
        log.info("tab -> \(tab.rawValue, privacy: .public)")
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
        guard let screen = currentScreen else { return }
        collapseTask?.cancel()
        collapseTask = nil
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
    }

    private func closePanel() {
        openTask?.cancel()
        viewModel.setSelectedTab(nil)
        // Shrink the window only after the close animation has finished,
        // otherwise it would clip the panel mid-flight.
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(NotchMetrics.windowCollapseDelayMilliseconds))
            guard !Task.isCancelled, let self else { return }
            self.collapseTask = nil
            self.applyCollapsedFrame()
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
            withInstantTransaction {
                viewModel.setSelectedTab(nil)
            }
            applyCollapsedFrame()
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
        applyCollapsedFrame(animated: true)
    }

    // MARK: - Frames

    private var iconCount: Int {
        max(settings.orderedEnabledTabs.count, 1)
    }

    private var currentScreen: NSScreen? {
        screen ?? NotchGeometry.targetScreen
    }

    private func applyCollapsedFrame(animated: Bool = false) {
        guard let screen = currentScreen else { return }
        let strip = WidgetGeometry.stripFrame(
            edge: settings.widgetEdge,
            offset: settings.widgetOffset,
            iconCount: iconCount,
            on: screen
        )
        panel.setFrame(strip, display: true, animate: animated)
        viewModel.stripFrame = CGRect(origin: .zero, size: strip.size)
        viewModel.panelFrame = .zero
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
        viewModel.stripFrame = layout.stripLocal
        viewModel.panelFrame = layout.panelLocal
    }

    /// State change with implicit animations suppressed (drag/display
    /// changes want instant collapse, not a clipped spring).
    private func withInstantTransaction(_ body: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }
}
