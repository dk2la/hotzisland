import AppKit
import Observation
import OSLog

/// Single countdown timer. Wall-clock based, so it stays correct through
/// display sleep and timer-tick coalescing.
@MainActor
@Observable
final class TimerService {
    private(set) var duration: TimeInterval = 25 * 60
    private(set) var remaining: TimeInterval = 25 * 60
    private(set) var isRunning = false

    /// The island flips between closed and compact on these.
    @ObservationIgnored var onRunningChanged: (() -> Void)?
    @ObservationIgnored var onFinished: (() -> Void)?

    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "timer")

    static let presets: [TimeInterval] = [5 * 60, 10 * 60, 25 * 60, 45 * 60]

    func setDuration(_ newDuration: TimeInterval) {
        guard !isRunning else { return }
        duration = newDuration
        remaining = newDuration
    }

    func start() {
        guard !isRunning, remaining > 0 else { return }
        isRunning = true
        endDate = Date().addingTimeInterval(remaining)
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.tick()
            }
        }
        log.info("started, \(Int(self.remaining), privacy: .public)s")
        onRunningChanged?()
    }

    func pause() {
        guard isRunning else { return }
        isRunning = false
        tickTask?.cancel()
        endDate = nil
        onRunningChanged?()
    }

    func reset() {
        pause()
        remaining = duration
    }

    private func tick() {
        guard isRunning, let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 {
            finish()
        }
    }

    private func finish() {
        isRunning = false
        tickTask?.cancel()
        endDate = nil
        remaining = duration
        NSSound(named: "Glass")?.play()
        onFinished?()
        onRunningChanged?()
    }
}
