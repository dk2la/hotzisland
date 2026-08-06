import SwiftUI

/// Content of the expanded island: module area + tab bar. The top strip is
/// kept clear of the camera housing.
struct ExpandedPanelView: View {
    var viewModel: NotchViewModel
    var power: PowerSourceMonitor
    var audio: AudioSystemMonitor
    var media: MediaCenter
    var calendar: CalendarService
    let notchHeight: CGFloat

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
        switch viewModel.selectedTab {
        case .devices:
            DevicesModuleView(power: power, audio: audio)
        case .media:
            MediaModuleView(media: media)
        case .calendar:
            CalendarModuleView(service: calendar)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 22) {
            ForEach(NotchTab.allCases) { tab in
                Button {
                    viewModel.selectTab(tab)
                } label: {
                    Image(systemName: tab.icon)
                        .font(Theme.tabIconFont)
                        .foregroundStyle(viewModel.selectedTab == tab ? Theme.textPrimary : Theme.textQuaternary)
                        .frame(width: 28, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
