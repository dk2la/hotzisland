import AppKit
import Observation
import OSLog

/// Executes playbooks: close → open → shortcut → timer. Closing is always
/// the polite `terminate()` (⌘Q semantics) — apps with unsaved work show
/// their own dialogs and may refuse; that is respected, never forced.
@MainActor
@Observable
final class PlaybookRunner {
    struct RunRecord {
        let playbook: Playbook
        let result: PlaybookRunResult
    }

    private(set) var isRunning = false
    private(set) var lastResult: PlaybookRunResult?
    /// Latest completed run — shown as the amber "run" register in the tab.
    private(set) var lastRun: RunRecord?

    /// Fired after a run completes — the window controller shows the
    /// confirmation event on the island.
    @ObservationIgnored var onFinished: ((Playbook, PlaybookRunResult) -> Void)?

    @ObservationIgnored private let timer: TimerService
    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "playbooks")

    /// Apps that are never closed, regardless of playbook contents.
    @ObservationIgnored private let neverClose: Set<String> = [
        "com.apple.finder",
        Bundle.main.bundleIdentifier ?? "com.dk2la.hotzisland",
    ]

    init(timer: TimerService) {
        self.timer = timer
    }

    func run(_ playbook: Playbook) {
        guard !isRunning else { return }
        isRunning = true
        var result = PlaybookRunResult()

        if playbook.closeOthers {
            result.closed = closeApps(keeping: Set(playbook.openBundleIDs))
        }
        openApps(playbook.openBundleIDs, into: &result)

        if let shortcutName = playbook.shortcutName, !shortcutName.isEmpty {
            runShortcut(named: shortcutName, into: &result)
        }

        if let minutes = playbook.timerMinutes, minutes > 0 {
            timer.reset()
            timer.setDuration(TimeInterval(minutes * 60))
            timer.start()
        }

        log.info("""
        ran "\(playbook.name, privacy: .public)": closed=\(result.closed, privacy: .public) \
        opened=\(result.opened, privacy: .public) \
        failures=\(result.failures.joined(separator: ","), privacy: .public)
        """)
        lastResult = result
        lastRun = RunRecord(playbook: playbook, result: result)
        isRunning = false
        onFinished?(playbook, result)
    }

    private func closeApps(keeping keep: Set<String>) -> Int {
        var closed = 0
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  !neverClose.contains(bundleID),
                  !keep.contains(bundleID)
            else { continue }
            if app.terminate() {
                closed += 1
            }
        }
        return closed
    }

    private func openApps(_ bundleIDs: [String], into result: inout PlaybookRunResult) {
        for bundleID in bundleIDs {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                result.failures.append(bundleID)
                continue
            }
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
            result.opened += 1
        }
    }

    /// Focus modes have no public API — a Shortcuts shortcut (with a
    /// "Set Focus" action) is the standard bridge. Fire-and-forget: the CLI
    /// returns after the shortcut finishes, which can take a while.
    private func runShortcut(named name: String, into result: inout PlaybookRunResult) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            result.failures.append("shortcut: \(name)")
        }
    }
}
