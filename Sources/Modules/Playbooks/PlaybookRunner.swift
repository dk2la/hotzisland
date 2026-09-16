import AppKit
import Observation
import OSLog

/// Executes a playbook's steps in order, asynchronously on the main actor.
/// Closing is always the polite `terminate()` (⌘Q semantics) — apps with
/// unsaved work show their own dialogs and may refuse; that is respected,
/// never forced.
@MainActor
@Observable
final class PlaybookRunner {
    struct RunRecord: Equatable {
        let playbook: Playbook
        let result: PlaybookRunResult
        let finishedAt: Date
    }

    /// True for the whole run — launches and window arranging take time.
    private(set) var isRunning = false
    /// The playbook currently executing, for the module's per-row state.
    private(set) var runningPlaybookID: UUID?
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
        runningPlaybookID = playbook.id
        Task { [weak self] in
            guard let self else { return }
            var result = PlaybookRunResult()
            for step in playbook.steps {
                await perform(step, of: playbook, into: &result)
            }
            finish(playbook, result: result)
        }
    }

    private func finish(_ playbook: Playbook, result: PlaybookRunResult) {
        log.info("""
        ran "\(playbook.name, privacy: .public)": closed=\(result.closed, privacy: .public) \
        opened=\(result.opened, privacy: .public) \
        failures=\(result.failures.joined(separator: ","), privacy: .public)
        """)
        lastResult = result
        lastRun = RunRecord(playbook: playbook, result: result, finishedAt: Date())
        isRunning = false
        runningPlaybookID = nil
        onFinished?(playbook, result)
    }

    // MARK: - Steps

    private func perform(_ step: PlaybookStep, of playbook: Playbook, into result: inout PlaybookRunResult) async {
        switch step {
        case .openApps(_, let bundleIDs, let layout):
            var launched: [String] = []
            for bundleID in bundleIDs {
                if await launch(bundleID) {
                    launched.append(bundleID)
                    result.opened += 1
                } else {
                    result.failures.append(bundleID)
                }
            }
            if layout != .none, !launched.isEmpty {
                await WindowLayoutService().arrange(bundleIDs: launched, layout: layout, on: NSScreen.main)
            }

        case .closeOtherApps:
            result.closed += closeApps(keeping: Set(playbook.appBundleIDs))

        case .runShortcut(_, let name):
            runShortcut(named: name, into: &result)

        case .setFocus(_, let shortcutName):
            runShortcut(named: shortcutName, into: &result)

        case .startTimer(_, let minutes):
            guard minutes > 0 else { return }
            timer.reset()
            timer.setDuration(TimeInterval(minutes * 60))
            timer.start()

        case .openURLs(_, let urls):
            for raw in urls {
                if let url = Self.url(from: raw) {
                    NSWorkspace.shared.open(url)
                } else {
                    result.failures.append("url: \(raw)")
                }
            }
        }
    }

    /// Launches (or activates) the app and waits until the system reports
    /// it running, so a following layout step has windows to move.
    private func launch(_ bundleID: String) async -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                continuation.resume(returning: error == nil)
            }
        }
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

    /// Focus modes have no public API — a Shortcuts shortcut (with a
    /// "Set Focus" action) is the standard bridge. Fire-and-forget: the CLI
    /// returns after the shortcut finishes, which can take a while. stderr
    /// is drained on its own handle so a chatty shortcut never blocks.
    private func runShortcut(named name: String, into result: inout PlaybookRunResult) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            result.failures.append("shortcut: (empty)")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", trimmed]
        process.standardOutput = FileHandle.nullDevice
        let stderr = Pipe()
        process.standardError = stderr
        let log = self.log
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                log.error("shortcut \"\(trimmed, privacy: .public)\": \(text, privacy: .public)")
            }
        }
        do {
            try process.run()
        } catch {
            stderr.fileHandleForReading.readabilityHandler = nil
            result.failures.append("shortcut: \(trimmed)")
        }
    }

    /// "example.com/x" is a link the user meant; `URL(string:)` alone
    /// would accept it as a relative path and `open` would do nothing.
    private static func url(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://" + trimmed)
    }
}
