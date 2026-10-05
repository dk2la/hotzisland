import Foundation
import Observation
import OSLog

/// Demo mode: every module shows scripted, lived-in data instead of the
/// user's own — for screenshots and promo recordings. Each store keeps its
/// real state aside while the mode is on and gets it back when it is off;
/// nothing the demo shows is written to defaults, Keychain or caches. The
/// flag itself is session-only, so a restart always comes back real;
/// `--demo` at launch turns it on at once.
@MainActor
@Observable
final class DemoMode {
    private(set) var isActive = false

    /// Shows a live event on the island — wired by the AppDelegate, which
    /// owns the notch controller.
    @ObservationIgnored var presentEvent: ((LiveEvent) -> Void)?

    @ObservationIgnored private weak var services: ModuleServices?
    @ObservationIgnored private var scratchFolder: URL?
    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "demo")

    /// Sample events for the "island events" buttons in settings, in the
    /// order they are shown.
    static let sampleEvents: [(label: String, event: LiveEvent)] = [
        ("pwr", .charging(percent: 82, plugged: true)),
        ("out", .audioDevice(name: "AirPods Pro")),
        ("vol", .volume(level: 0.55)),
        ("timer", .timerFinished),
        ("run", .playbookRan(name: "Morning review")),
    ]

    func attach(services: ModuleServices) {
        self.services = services
    }

    func setActive(_ active: Bool) {
        if active { activate() } else { deactivate() }
    }

    func activate() {
        guard !isActive, let services else { return }
        isActive = true
        let folder = DemoFixtures.makeScratchFolder()
        scratchFolder = folder

        services.emailService.enterDemo(
            account: DemoFixtures.emailAccount,
            folders: DemoFixtures.mailFolders,
            lists: DemoFixtures.mailLists()
        )
        let calendar = services.calendarService
        calendar.enterDemo(
            calendars: DemoFixtures.calendars,
            events: DemoFixtures.calendarEvents(calendar: calendar.calendar)
        )
        services.mediaCenter.enterDemo()
        services.statsService.enterDemo()
        services.powerMonitor.enterDemo(percent: 82, plugged: false)
        services.audioMonitor.enterDemo(volume: 0.55, deviceName: "AirPods Pro")
        services.clipboardStore.enterDemo(entries: DemoFixtures.clipboardEntries())
        services.shelfStore.enterDemo(urls: DemoFixtures.shelfFiles(in: folder))
        services.notesStore.enterDemo(folder: DemoFixtures.notesFolder(in: folder))
        services.playbookStore.enterDemo(playbooks: DemoFixtures.playbooks)
        services.assistantService.enterDemo(transcript: DemoFixtures.assistantTranscript())
        let timer = services.timerService
        timer.reset()
        timer.setDuration(25 * 60)
        log.info("demo mode on")
    }

    func deactivate() {
        guard isActive, let services else { return }
        isActive = false
        services.emailService.exitDemo()
        services.calendarService.exitDemo()
        services.mediaCenter.exitDemo()
        services.statsService.exitDemo()
        services.powerMonitor.exitDemo()
        services.audioMonitor.exitDemo()
        services.clipboardStore.exitDemo()
        services.shelfStore.exitDemo()
        services.notesStore.exitDemo()
        services.playbookStore.exitDemo()
        services.assistantService.exitDemo()
        if let scratchFolder {
            try? FileManager.default.removeItem(at: scratchFolder)
        }
        scratchFolder = nil
        log.info("demo mode off")
    }

    /// Flashes a sample event on the island.
    func fire(_ event: LiveEvent) {
        presentEvent?(event)
    }
}
