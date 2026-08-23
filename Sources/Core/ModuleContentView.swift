import SwiftUI

/// One module's content, shared by the expanded island panel and the edge
/// widget — the single place a tab maps to its view.
struct ModuleContentView: View {
    let tab: NotchTab
    var services: ModuleServices
    var playbooks: PlaybookStore

    var body: some View {
        switch tab {
        case .playbooks:
            PlaybooksModuleView(store: playbooks, runner: services.playbookRunner)
        case .media:
            MediaModuleView(media: services.mediaCenter)
        case .calendar:
            CalendarModuleView(service: services.calendarService)
        case .metrics:
            MetricsModuleView(
                stats: services.statsService,
                power: services.powerMonitor,
                audio: services.audioMonitor
            )
        case .shelf:
            ShelfModuleView(shelf: services.shelfStore)
        case .clipboard:
            ClipboardModuleView(clipboard: services.clipboardStore)
        case .timer:
            TimerModuleView(timer: services.timerService)
        }
    }
}
