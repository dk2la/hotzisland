import SwiftUI

/// Root of the widget window: an edge-docked icon strip plus, when a module
/// is open, its panel beside the strip. Both are positioned by the
/// controller in window-local coordinates.
struct WidgetRootView: View {
    var viewModel: WidgetViewModel
    var services: ModuleServices
    var settings: AppSettings
    var playbooks: PlaybookStore

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WidgetMetrics.radius, style: .continuous)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let tab = viewModel.selectedTab {
                panel(for: tab)
                    .frame(width: viewModel.panelFrame.width, height: viewModel.panelFrame.height)
                    .offset(x: viewModel.panelFrame.minX, y: viewModel.panelFrame.minY)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: panelAnchor)))
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

    // MARK: - Strip

    private var strip: some View {
        InstrumentShell(
            shape: shape,
            theme: settings.theme,
            accent: services.mediaCenter.artworkAccent
        )
        .overlay(shape.stroke(Theme.islandBorder, lineWidth: 1))
        .overlay { stripContent }
        .clipShape(shape)
        .contentShape(shape)
        .gesture(dragGesture)
    }

    private var stripContent: some View {
        let layout = viewModel.edge.isVertical
            ? AnyLayout(VStackLayout(spacing: WidgetMetrics.spacing))
            : AnyLayout(HStackLayout(spacing: WidgetMetrics.spacing))
        return layout {
            gripDots
            ForEach(settings.orderedEnabledTabs) { tab in
                iconButton(for: tab)
            }
        }
        .padding(viewModel.edge.isVertical ? .vertical : .horizontal, WidgetMetrics.endPadding)
    }

    private func iconButton(for tab: NotchTab) -> some View {
        let isActive = viewModel.selectedTab == tab
        return Button {
            viewModel.onTabTapped?(tab)
        } label: {
            Image(systemName: tab.icon)
                .font(Theme.tabIconFont)
                .foregroundStyle(isActive ? Theme.accent : Theme.textQuaternary)
                .frame(width: WidgetMetrics.cell, height: WidgetMetrics.cell)
                .background(
                    isActive ? Theme.accentWash : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.cardRadius)
                )
                .contentShape(Rectangle())
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
                    .fill(Theme.textFaint)
                    .frame(width: 2.5, height: 2.5)
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

    // MARK: - Panel

    private func panel(for tab: NotchTab) -> some View {
        InstrumentShell(
            shape: shape,
            theme: settings.theme,
            accent: services.mediaCenter.artworkAccent
        )
        .overlay(shape.stroke(Theme.islandBorder, lineWidth: 1))
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
        .clipShape(shape)
    }

    private func panelHeader(for tab: NotchTab) -> some View {
        HStack(spacing: 0) {
            Text(tab.channelLabel.uppercased())
                .font(Theme.labelFont)
                .kerning(1.1)
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
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Hairline(color: Theme.hairline)
        }
    }
}
