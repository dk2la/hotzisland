import Foundation

/// Single shared instances of every module service. Both the notch island
/// and the edge widget render from these — separate copies would diverge
/// (two clipboard histories) or double the work (two media pollers).
@MainActor
final class ModuleServices {
    let powerMonitor = PowerSourceMonitor()
    let audioMonitor = AudioSystemMonitor()
    let mediaCenter = MediaCenter()
    let calendarService = CalendarService()
    let statsService = SystemStatsService()
    let shelfStore = ShelfStore()
    let clipboardStore = ClipboardStore()
    let timerService = TimerService()
    let notesStore = NotesStore()
    let speechCapture = SpeechCaptureService()
    let speechSynthesis = SpeechSynthesisService()
    let emailService = EmailService()
    let assistantService = AssistantService()
    let playbookStore = PlaybookStore()
    let playbookRunner: PlaybookRunner

    init() {
        playbookRunner = PlaybookRunner(timer: timerService)
        // The toolbox needs the fully built container, so it attaches last.
        assistantService.attachToolbox(services: self, playbooks: playbookStore)
    }
}
