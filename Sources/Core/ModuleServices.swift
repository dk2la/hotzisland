/// Single shared instances of every module service. Both the capsule
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
    let senderAvatars = SenderAvatarStore()
    let assistantService = AssistantService()
    let playbookStore = PlaybookStore()
    let playbookRunner: PlaybookRunner
    let appShortcuts = AppShortcutsService()
    /// Scripted data in every module, for promo recordings.
    let demo = DemoMode()
    /// Global shortcuts — the AppDelegate binds their actions, Settings →
    /// Hotkeys rebinds their keys.
    let hotkeys = HotkeyService()

    init() {
        playbookRunner = PlaybookRunner(timer: timerService)
        // The toolbox needs the fully built container, so it attaches last.
        assistantService.attachToolbox(services: self)
        demo.attach(services: self)
    }

    /// Starts everything that makes macOS ask for access on its own: the
    /// notes folder (Documents by default), the clipboard, scripting the
    /// music players. On first launch the welcome tour calls it once it is
    /// closed — its pages ask for the calendar and the notes folder first.
    func beginProtectedAccess() {
        notesStore.activate()
        clipboardStore.startWatching()
        mediaCenter.allowPlayerScripts()
    }
}
