import SwiftUI

/// One module's content, shared by the expanded capsule panel and the edge
/// widget — the single place a tab maps to its view.
struct ModuleContentView: View {
    let tab: ModuleTab
    var services: ModuleServices

    var body: some View {
        switch tab {
        case .playbooks:
            PlaybooksModuleView(store: services.playbookStore, runner: services.playbookRunner)
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
        case .notes:
            NotesModuleView(store: services.notesStore, speech: services.speechCapture)
        case .email:
            EmailModuleView(service: services.emailService, speech: services.speechCapture, avatars: services.senderAvatars)
        case .assistant:
            AssistantModuleView(
                assistant: services.assistantService,
                speech: services.speechCapture,
                voice: services.speechSynthesis
            )
        case .hotkeys:
            AppShortcutsModuleView(service: services.appShortcuts)
        case .chats:
            ComingSoonModuleView(tab: tab)
        }
    }
}
