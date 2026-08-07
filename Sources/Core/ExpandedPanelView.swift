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
    }

    @ViewBuilder
    private var content: some View {
        switch effectiveTab {
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
