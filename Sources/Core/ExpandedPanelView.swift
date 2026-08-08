import OSLog
import SwiftUI

/// Content of the expanded island: module area + tab bar. The top strip is
/// kept clear of the camera housing.
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

    private var enabledTabs: [NotchTab] {
        NotchTab.allCases.filter { settings.isEnabled($0) }
    }

    /// The selected tab may have been disabled in settings — fall back to
    /// the first enabled one.
    private var effectiveTab: NotchTab {
        settings.isEnabled(viewModel.selectedTab)
            ? viewModel.selectedTab
            : (enabledTabs.first ?? .devices)
    }

    @State private var resizeStartSize: CGSize?

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 4)
            tabBar
                .padding(.bottom, 10)
        }
        .overlay(alignment: .bottomTrailing) {
            resizeGrip
                // Kept clear of the capsule's rounded corner: clipShape also
                // clips hit-testing, so a grip in the corner curve is
                // unclickable.
                .padding(.trailing, 18)
                .padding(.bottom, 7)
        }
    }

    @State private var resizeStartGlobal: CGPoint?

    /// Corner grip: drag to resize the panel like an app window. Width grows
    /// symmetrically (the island stays centered under the notch). Tracking
    /// uses the global cursor position — the window moves mid-drag, so local
    /// gesture coordinates would feed back into themselves.
    private var resizeGrip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Theme.textQuaternary)
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
                            Logger(subsystem: "com.dk2la.hotzisland", category: "settings")
                                .info("grip drag began")
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

    @ViewBuilder
    private var content: some View {
        switch effectiveTab {
        case .playbooks:
            PlaybooksModuleView(store: playbooks, runner: playbookRunner)
        case .devices:
            DevicesModuleView(power: power, audio: audio)
        case .media:
            MediaModuleView(media: media)
        case .calendar:
            CalendarModuleView(service: calendar)
        case .metrics:
            MetricsModuleView(stats: stats)
        case .shelf:
            ShelfModuleView(shelf: shelf)
        case .clipboard:
            ClipboardModuleView(clipboard: clipboard)
        case .timer:
            TimerModuleView(timer: timer)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 22) {
            ForEach(enabledTabs) { tab in
                Button {
                    viewModel.selectTab(tab)
                } label: {
                    Image(systemName: tab.icon)
                        .font(Theme.tabIconFont)
                        .foregroundStyle(effectiveTab == tab ? Theme.textPrimary : Theme.textQuaternary)
                        .frame(width: 28, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
