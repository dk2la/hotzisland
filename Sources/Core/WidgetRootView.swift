import SwiftUI

/// Root of the widget window: an edge-docked ornament (icon capsule) plus,
/// when a module is open, its glass window beside it. Both are positioned by
/// the controller in window-local coordinates. V3: visionOS glass material,
/// circular cells, solid-white selected state.
struct WidgetRootView: View {
    var viewModel: WidgetViewModel
    var services: ModuleServices
    var settings: AppSettings

    @Environment(\.colorScheme) private var colorScheme
    var playbooks: PlaybookStore

    private var stripShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WidgetMetrics.radius, style: .continuous)
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.windowRadius, style: .continuous)
    }

    private var darkGlass: Bool {
        settings.glassAppearance.resolvedDark(for: colorScheme)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let tab = viewModel.selectedTab {
                panel(for: tab)
                    .frame(width: viewModel.panelFrame.width, height: viewModel.panelFrame.height)
                    .offset(x: viewModel.panelFrame.minX, y: viewModel.panelFrame.minY)
                    .transition(panelTransition)
            }
            strip
                .frame(width: viewModel.stripFrame.width, height: viewModel.stripFrame.height)
                .offset(x: viewModel.stripFrame.minX, y: viewModel.stripFrame.minY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Theme.stateSpring, value: viewModel.selectedTab)
        .animation(Theme.stateSpring, value: viewModel.edge)
    }

    /// The panel grows out of the side that faces the strip.
    private var panelAnchor: UnitPoint {
        switch viewModel.edge {
        case .left: .leading
        case .right: .trailing
        case .top: .top
        case .bottom: .bottom
        }
    }

    /// Asymmetric on purpose: opening earns the scale-in, closing is the
    /// user already done — a plain fade gets out of the way faster. Reduce
    /// Motion drops the positional scale entirely.
    private var panelTransition: AnyTransition {
        Theme.reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: panelAnchor)),
                removal: .opacity
            )
    }

    // MARK: - Ornament strip

    private var strip: some View {
        GlassSurface(shape: stripShape, dark: darkGlass)
            .overlay { stripContent }
            .clipShape(stripShape)
            .contentShape(stripShape)
            .gesture(dragGesture)
            // Minimized: a click on the dots brings the icons back. The drag
            // gesture keeps priority, so moving the widget still works.
            .onTapGesture {
                if viewModel.isMinimized { viewModel.onRestore?() }
            }
            .help(viewModel.isMinimized ? L10n.t(.setHideWidget) : "")
            .contextMenu {
                Button(L10n.t(.menuSettings)) {
                    NotificationCenter.default.post(name: .hotzOpenSettings, object: nil)
                }
                Button(L10n.t(.menuIslandMode)) {
                    settings.displayMode = .island
                }
                Divider()
                Button(L10n.t(.menuQuit)) {
                    NSApplication.shared.terminate(nil)
                }
            }
    }

    /// Minimized keeps the grip only — same view identity, so the strip
    /// shrinks around the dots instead of being swapped for another shape.
    private var stripContent: some View {
        let layout = viewModel.edge.isVertical
            ? AnyLayout(VStackLayout(spacing: WidgetMetrics.spacing))
            : AnyLayout(HStackLayout(spacing: WidgetMetrics.spacing))
        return layout {
            gripDots
            ForEach(visibleTabs) { tab in
                RailIconButton(
                    tab: tab,
                    isActive: viewModel.selectedTab == tab,
                    showsBadge: tab == .email && services.emailService.unreadCount > 0
                ) {
                    viewModel.onTabTapped?(tab)
                }
            }
        }
        .padding(viewModel.edge.isVertical ? .vertical : .horizontal, WidgetMetrics.endPadding)
    }

    /// Minimized the strip keeps its first module button — the widget still
    /// reads as itself, and that one button unfolds it.
    private var visibleTabs: [NotchTab] {
        let tabs = settings.orderedEnabledTabs
        return viewModel.isMinimized ? Array(tabs.prefix(1)) : tabs
    }

    /// Drag handle at the strip's leading end. Dots run across the strip's
    /// axis, like a hardware grip.
    private var gripDots: some View {
        let layout = viewModel.edge.isVertical
            ? AnyLayout(HStackLayout(spacing: 3))
            : AnyLayout(VStackLayout(spacing: 3))
        return layout {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(Theme.textPrimary.opacity(0.4))
                    .frame(width: 3, height: 3)
            }
        }
        .frame(
            width: viewModel.edge.isVertical ? WidgetMetrics.cell : WidgetMetrics.gripSize,
            height: viewModel.edge.isVertical ? WidgetMetrics.gripSize : WidgetMetrics.cell
        )
        .contentShape(Rectangle())
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { _ in viewModel.onDragChanged?() }
            .onEnded { _ in viewModel.onDragEnded?() }
    }

    // MARK: - Panel window

    private func panel(for tab: NotchTab) -> some View {
        GlassSurface(shape: panelShape, dark: darkGlass)
            .overlay {
                VStack(spacing: 0) {
                    PanelHeaderView(tab: tab, services: services) {
                        viewModel.onClose?()
                    }
                    ModuleContentView(tab: tab, services: services, playbooks: playbooks)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, Theme.panelInset)
                        .padding(.top, Theme.panelInset)
                        .padding(.bottom, 10)
                }
            }
            .clipShape(panelShape)
            .overlay(alignment: widthGripAlignment) { widthGrip }
            .overlay(alignment: heightGripAlignment) { heightGrip }
    }

    /// Each grip lives on an edge facing away from the strip — a side the
    /// panel actually grows toward.
    private var widthGripAlignment: Alignment {
        viewModel.edge == .right ? .leading : .trailing
    }

    private var heightGripAlignment: Alignment {
        viewModel.edge == .bottom ? .top : .bottom
    }

    private var widthGrip: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Theme.textPrimary.opacity(0.22))
            .frame(width: 3, height: 34)
            .frame(width: 14)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { _ in viewModel.onResizeChanged?() }
                    .onEnded { _ in viewModel.onResizeEnded?() }
            )
            .onHover { inside in
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    /// One rail cell. A struct, not a builder func — hover feedback needs
    /// its own state per cell.
    private struct RailIconButton: View {
        let tab: NotchTab
        let isActive: Bool
        let showsBadge: Bool
        let action: () -> Void

        @State private var hovered = false

        var body: some View {
            let cellShape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            Button(action: action) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isActive ? Theme.accent : Theme.textSecondary)
                    .frame(width: WidgetMetrics.cell, height: WidgetMetrics.cell)
                    .background(
                        cellShape.fill(isActive ? Theme.accentWash : hovered ? Theme.raisedFill : .clear)
                    )
                    .overlay(alignment: .topTrailing) {
                        if showsBadge {
                            Circle()
                                .fill(Theme.critical)
                                .frame(width: 5, height: 5)
                                .padding(6)
                        }
                    }
                    .contentShape(cellShape)
            }
            .buttonStyle(PressableStyle())
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.15), value: hovered)
            // Eight abstract glyphs need names — the system tooltip is free.
            .help(tab.title)
        }
    }

    private var heightGrip: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Theme.textPrimary.opacity(0.22))
            .frame(width: 34, height: 3)
            .frame(height: 14)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { _ in viewModel.onHeightResizeChanged?() }
                    .onEnded { _ in viewModel.onHeightResizeEnded?() }
            )
            .onHover { inside in
                if inside {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

}
