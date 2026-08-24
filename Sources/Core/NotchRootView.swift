import SwiftUI

struct NotchRootView: View {
    var viewModel: NotchViewModel
    var services: ModuleServices
    var settings: AppSettings
    var playbooks: PlaybookStore
    let closedSize: CGSize

    private var isExpanded: Bool { viewModel.state == .expanded }

    private var islandSize: CGSize {
        if isExpanded { return settings.expandedPanelSize }
        if viewModel.activeEvent != nil {
            return CGSize(
                width: closedSize.width + NotchMetrics.eventSideWidth * 2,
                height: closedSize.height
            )
        }
        if viewModel.state == .compact,
           services.timerService.isRunning || services.mediaCenter.track != nil {
            return CGSize(
                width: closedSize.width + NotchMetrics.compactSideWidth * 2,
                height: closedSize.height
            )
        }
        return closedSize
    }

    private var shape: NotchShape {
        NotchShape(
            topRadius: isExpanded ? NotchMetrics.expandedTopRadius : NotchMetrics.closedTopRadius,
            bottomRadius: isExpanded ? NotchMetrics.expandedBottomRadius : NotchMetrics.closedBottomRadius
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var island: some View {
        InstrumentShell(
            shape: shape,
            theme: settings.theme,
            accent: services.mediaCenter.artworkAccent
        )
            .overlay {
                if isExpanded {
                    expandedContent
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .top)))
                } else if let event = viewModel.activeEvent {
                    LiveEventView(event: event)
                        .transition(.opacity)
                } else if viewModel.state == .compact, services.timerService.isRunning {
                    // A running timer outranks media: it is the thing the
                    // user explicitly started and it has a deadline.
                    CompactTimerView(timer: services.timerService)
                        .transition(.opacity)
                } else if viewModel.state == .compact, let track = services.mediaCenter.track {
                    CompactMediaView(track: track, artwork: services.mediaCenter.artwork)
                        .transition(.opacity)
                }
            }
            .clipShape(shape)
            .frame(width: islandSize.width, height: islandSize.height)
            .animation(Theme.stateSpring, value: viewModel.state)
            .animation(Theme.stateSpring, value: viewModel.selectedTab)
            .dropDestination(for: URL.self) { urls, _ in
                services.shelfStore.add(urls)
                return !urls.isEmpty
            } isTargeted: { targeted in
                if targeted {
                    viewModel.onDragTargeted?()
                }
            }
            .animation(Theme.eventSpring, value: viewModel.activeEvent)
    }

    private var expandedContent: some View {
        ExpandedPanelView(
            viewModel: viewModel,
            services: services,
            settings: settings,
            playbooks: playbooks,
            notchHeight: closedSize.height
        )
    }
}
