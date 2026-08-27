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
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: panelAnchor)))
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
                iconButton(for: tab)
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

    private func iconButton(for tab: NotchTab) -> some View {
        let isActive = viewModel.selectedTab == tab
        let cellShape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            viewModel.onTabTapped?(tab)
        } label: {
            Image(systemName: tab.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? Theme.accent : Theme.textPrimary.opacity(0.6))
                .frame(width: WidgetMetrics.cell, height: WidgetMetrics.cell)
                .background(cellShape.fill(isActive ? Theme.accentWash : .clear))
                .overlay(alignment: .topTrailing) {
                    if tab == .email, services.emailService.unreadCount > 0 {
                        Circle()
                            .fill(Theme.critical)
                            .frame(width: 5, height: 5)
                            .padding(6)
                    }
                }
                .contentShape(cellShape)
        }
        .buttonStyle(PressableStyle())
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
                    panelHeader(for: tab)
                    ModuleContentView(tab: tab, services: services, playbooks: playbooks)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, Theme.panelInset)
                        .padding(.top, Theme.panelInset)
                        .padding(.bottom, 10)
                }
            }
            .clipShape(panelShape)
    }

    private func panelHeader(for tab: NotchTab) -> some View {
        HStack(spacing: 0) {
            Text(tab.title.uppercased())
                .font(Theme.labelFont)
                .kerning(1.2)
                .foregroundStyle(Theme.accent)
            Spacer(minLength: 0)
            Button {
                viewModel.onClose?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, Theme.panelInset)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Hairline(color: Theme.hairline)
        }
    }
}
