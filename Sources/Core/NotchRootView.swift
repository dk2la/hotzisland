import SwiftUI

struct NotchRootView: View {
    var viewModel: NotchViewModel
    var power: PowerSourceMonitor
    var audio: AudioSystemMonitor
    var media: MediaCenter
    var calendar: CalendarService
    var stats: SystemStatsService
    var shelf: ShelfStore
    var clipboard: ClipboardStore
    var timer: TimerService
    var settings: AppSettings
    var playbooks: PlaybookStore
    var playbookRunner: PlaybookRunner
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
        if viewModel.state == .compact, timer.isRunning || media.track != nil {
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

    /// Island shell per theme. Glass keeps a dark scrim over the material so
    /// content stays readable on bright wallpapers; Glow tints its ring with
    /// the artwork's average color.
    @ViewBuilder
    private var islandShell: some View {
        switch settings.theme {
        case .stealth:
            shape.fill(Theme.islandFill)
        case .glass:
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(Theme.islandFill.opacity(0.45)))
        case .glow:
            let accent = media.artworkAccent ?? Theme.textQuaternary
            shape.fill(Theme.islandFill)
                .overlay(shape.stroke(accent.opacity(0.9), lineWidth: 1).blur(radius: 2.5))
                .overlay(shape.stroke(accent.opacity(0.7), lineWidth: 1))
        }
    }

    private var island: some View {
        islandShell
            .overlay {
                if isExpanded {
                    expandedContent
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .top)))
                } else if let event = viewModel.activeEvent {
                    LiveEventView(event: event)
                        .transition(.opacity)
                } else if viewModel.state == .compact, timer.isRunning {
                    // A running timer outranks media: it is the thing the
                    // user explicitly started and it has a deadline.
                    CompactTimerView(timer: timer)
                        .transition(.opacity)
                } else if viewModel.state == .compact, let track = media.track {
                    CompactMediaView(track: track, artwork: media.artwork)
                        .transition(.opacity)
                }
            }
            .clipShape(shape)
            .frame(width: islandSize.width, height: islandSize.height)
            .animation(Theme.stateSpring, value: viewModel.state)
            .animation(Theme.stateSpring, value: viewModel.selectedTab)
            .dropDestination(for: URL.self) { urls, _ in
                shelf.add(urls)
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
            power: power,
            audio: audio,
            media: media,
            calendar: calendar,
            stats: stats,
            shelf: shelf,
            clipboard: clipboard,
            timer: timer,
            settings: settings,
            playbooks: playbooks,
            playbookRunner: playbookRunner,
            notchHeight: closedSize.height
        )
    }
}
