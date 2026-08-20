import OSLog
import SwiftUI

/// Content of the expanded island: channel-selector tab row on top (under
/// the camera housing), module content below.
struct ExpandedPanelView: View {
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
    let notchHeight: CGFloat

    @State private var resizeStartSize: CGSize?
    @State private var resizeStartGlobal: CGPoint?

    private var enabledTabs: [NotchTab] {
        settings.orderedEnabledTabs
    }

    /// The selected tab may have been disabled in settings — fall back to
    /// the first enabled one.
    private var effectiveTab: NotchTab {
        settings.isEnabled(viewModel.selectedTab)
            ? viewModel.selectedTab
            : (enabledTabs.first ?? .metrics)
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            channelSelector
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Theme.panelInset)
                .padding(.top, Theme.panelInset)
                .padding(.bottom, 10)
        }
        .overlay(alignment: .bottomTrailing) {
            resizeGrip
                // Kept clear of the capsule's rounded corner: clipShape also
                // clips hit-testing.
                .padding(.trailing, 16)
                .padding(.bottom, 6)
        }
    }

    /// Tab row styled as a hardware channel selector: mono caps, the active
    /// channel is amber with a 2px underline; hairline under the whole row.
    private var channelSelector: some View {
        HStack(spacing: 0) {
            ForEach(enabledTabs) { tab in
                let isActive = effectiveTab == tab
                Button {
                    viewModel.selectTab(tab)
                } label: {
                    Text(tab.channelLabel.uppercased())
                        .font(Theme.labelFont)
                        .kerning(1.1)
                        .foregroundStyle(isActive ? Theme.accent : Theme.textQuaternary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(isActive ? Theme.accent : .clear)
                                .frame(height: 2)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            Hairline(color: Theme.hairline)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch effectiveTab {
        case .playbooks:
            PlaybooksModuleView(store: playbooks, runner: playbookRunner)
        case .media:
            MediaModuleView(media: media)
        case .calendar:
            CalendarModuleView(service: calendar)
        case .metrics:
            MetricsModuleView(stats: stats, power: power, audio: audio)
        case .shelf:
            ShelfModuleView(shelf: shelf)
        case .clipboard:
            ClipboardModuleView(clipboard: clipboard)
        case .timer:
            TimerModuleView(timer: timer)
        }
    }

    /// Corner grip: drag to resize the panel like an app window. Tracking
    /// uses the global cursor position — the window moves mid-drag, so local
    /// gesture coordinates would feed back into themselves.
    private var resizeGrip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Theme.textFaint)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in
                        let now = NSEvent.mouseLocation
                        guard let start = resizeStartGlobal, let startSize = resizeStartSize else {
                            resizeStartGlobal = now
                            resizeStartSize = settings.expandedPanelSize
                            viewModel.isResizingPanel = true
                            return
                        }
                        // Cocoa coordinates: dragging down means decreasing y.
                        settings.setPanelSize(CGSize(
                            width: startSize.width + (now.x - start.x) * 2,
                            height: startSize.height + (start.y - now.y)
                        ))
                    }
                    .onEnded { _ in
                        resizeStartGlobal = nil
                        resizeStartSize = nil
                        viewModel.isResizingPanel = false
                    }
            )
    }
}
