import SwiftUI

struct NotchRootView: View {
    var viewModel: NotchViewModel
    var services: ModuleServices
    var settings: AppSettings
    var playbooks: PlaybookStore
    let closedSize: CGSize

    private var isExpanded: Bool { viewModel.state == .expanded }

    /// The capsule around the housing: notch-sized at rest, wider for a
    /// live event or the compact indicators. Never wider while expanded —
    /// the panel grows below the menu bar instead.
    private var capsuleSize: CGSize {
        if isExpanded { return closedSize }
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

    private static var fillet: CGFloat { NotchMetrics.dropFillet }

    /// The housing itself, without the capsule's flares: the neck through
    /// the menu bar is exactly this wide, never more.
    private var notchWidth: CGFloat {
        max(0, closedSize.width - 2 * NotchMetrics.closedTopRadius)
    }

    /// The drop: a neck exactly the housing's width through the menu bar,
    /// concave shoulders just below it, then the panel. Collapsed it is
    /// exactly the housing — black on black, invisible — and both axes
    /// animate from there, so the menu bar beside the notch is never
    /// covered at any point.
    private var dropSize: CGSize {
        if isExpanded {
            return CGSize(
                width: settings.expandedPanelSize.width,
                height: settings.expandedPanelSize.height + closedSize.height + Self.fillet
            )
        }
        // Shorter than the capsule by its bottom radius: the sliver's square
        // bottom stays hidden above the capsule's rounded corners.
        return CGSize(
            width: notchWidth,
            height: max(0, closedSize.height - NotchMetrics.closedBottomRadius - 2)
        )
    }

    private var capsuleShape: NotchShape {
        NotchShape(
            topRadius: NotchMetrics.closedTopRadius,
            bottomRadius: NotchMetrics.closedBottomRadius
        )
    }

    private var dropShape: NotchDropShape {
        NotchDropShape(
            neckWidth: notchWidth,
            neckHeight: closedSize.height + Self.fillet,
            fillet: Self.fillet
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            drop
            // The flared capsule belongs to the resting states; expanded,
            // the exact-width neck takes over and the flares fade away.
            capsule
                .opacity(isExpanded ? 0 : 1)
                .animation(Theme.stateSpring, value: isExpanded)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The notch capsule: live events and compact indicators live here.
    private var capsule: some View {
        InstrumentShell(
            shape: capsuleShape,
            theme: settings.theme,
            accent: services.mediaCenter.artworkAccent
        )
            .overlay {
                if isExpanded {
                    EmptyView()
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
            .clipShape(capsuleShape)
            .contentShape(capsuleShape)
            // A click on the resting island opens the settings; the expanded
            // panel hosts its own controls, so the tap is inert there.
            .onTapGesture {
                if !isExpanded { viewModel.onIslandTapped?() }
            }
            .contextMenu {
                Button(L10n.t(.menuSettings)) {
                    viewModel.onIslandTapped?()
                }
                Divider()
                Button(L10n.t(.menuQuit)) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .frame(width: capsuleSize.width, height: capsuleSize.height)
            .animation(Theme.stateSpring, value: viewModel.state)
            // Files dropped on the notch still land on the shelf (which
            // lives in the widget).
            .dropDestination(for: URL.self) { urls, _ in
                services.shelfStore.add(urls)
                return !urls.isEmpty
            }
            .animation(Theme.eventSpring, value: viewModel.activeEvent)
    }

    /// The falling drop: one shape whose frame animates from a sliver
    /// behind the housing to the full panel, so nothing ever jumps.
    private var drop: some View {
        InstrumentShell(
            shape: dropShape,
            theme: settings.theme,
            accent: services.mediaCenter.artworkAccent
        )
            .overlay {
                if isExpanded {
                    expandedContent
                        .transition(.opacity)
                }
            }
            .clipShape(dropShape)
            .contentShape(dropShape)
            .frame(width: dropSize.width, height: dropSize.height)
            .animation(Theme.stateSpring, value: isExpanded)
    }

    private var expandedContent: some View {
        IslandSettingsView(
            viewModel: viewModel,
            services: services,
            settings: settings,
            playbooks: playbooks,
            notchHeight: closedSize.height + Self.fillet
        )
    }
}
