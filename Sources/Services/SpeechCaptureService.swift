import AppKit
import AVFoundation
import Foundation
import Observation
import OSLog
import Speech

/// Dictation: microphone → live transcript. Owned by ModuleServices so any
/// module (Notes, the assistant) can borrow the same recorder.
///
/// Pause survival — the hard part. The ON-DEVICE recognizer silently resets
/// its transcription after a pause in speech: no isFinal, no error, the next
/// partial simply starts from scratch (observed live on macOS 26). So the
/// service cannot wait for recognizer events; it detects utterance ends
/// itself and folds the finished piece into a committed prefix first:
/// - stall watcher: no new partials for ~1.6 s while text exists → roll;
/// - reset heuristic: a partial that shares no prefix with, and is shorter
///   than, the current segment is a new utterance → fold before replacing;
/// - isFinal / task death / the ~1 min request cap also roll, when they do
///   happen. The visible transcript only ever grows.
@MainActor
@Observable
final class SpeechCaptureService {
    enum Phase: Equatable {
        case idle
        case denied
        case starting
        case recording
        case stopping
    }

    private(set) var phase: Phase = .idle
    /// Live cumulative transcript (committed prefix + current segment).
    private(set) var transcript: String = ""
    private(set) var startedAt: Date?

    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "speech")
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private let requestBox = SpeechRequestBox()
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    /// Text committed by finished segments; `segment` is the live remainder.
    @ObservationIgnored private var prefix = ""
    @ObservationIgnored private var segment = ""
    /// Identifies the current segment: late callbacks from a cancelled task
    /// would otherwise overwrite the next segment's text.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var segmentStartedAt = Date.distantPast
    /// Restart storm brake — recognition failing the instant it starts.
    @ObservationIgnored private var instantFailures = 0
    /// When the last non-empty partial arrived — the stall watcher's clock.
    @ObservationIgnored private var lastPartialAt = Date.distantPast
    @ObservationIgnored private var stallWatcher: Task<Void, Never>?
    /// Partials stop flowing this long → the utterance is over; commit it
    /// before the on-device recognizer resets it.
    private static let stallInterval: TimeInterval = 1.6

    var isRecording: Bool { phase == .recording || phase == .starting }

    // MARK: - Lifecycle

    func start(locale: Locale) async {
        guard phase == .idle || phase == .denied else { return }
        phase = .starting

        guard await Self.requestPermissions() else {
            phase = .denied
            log.info("permissions denied")
            return
        }

        let recognizer = SFSpeechRecognizer(locale: locale)
            ?? SFSpeechRecognizer(locale: Locale.current)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
        guard let recognizer, recognizer.isAvailable else {
            phase = .idle
            log.error("recognizer unavailable for \(locale.identifier, privacy: .public)")
            return
        }
        self.recognizer = recognizer

        prefix = ""
        segment = ""
        transcript = ""
        instantFailures = 0

        do {
            try startEngineTap()
        } catch {
            phase = .idle
            log.error("audio engine failed: \(error, privacy: .public)")
            return
        }

        beginSegment()
        startedAt = Date()
        phase = .recording
        scheduleRestart()
        startStallWatcher()
        log.info("recording locale=\(locale.identifier, privacy: .public) onDevice=\(recognizer.supportsOnDeviceRecognition, privacy: .public)")
    }

    /// Stops the engine and returns the final transcript.
    func stop() async -> String {
        guard isRecording else { return "" }
        phase = .stopping
        restartTask?.cancel()
        stallWatcher?.cancel()
        stallWatcher = nil
        requestBox.request?.endAudio()
        // Give the recognizer a beat to deliver the final partials.
        try? await Task.sleep(for: .milliseconds(400))
        task?.cancel()
        task = nil
        requestBox.request = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        let final = composedTranscript()
        prefix = ""
        segment = ""
        transcript = ""
        startedAt = nil
        phase = .idle
        log.info("stopped chars=\(final.count, privacy: .public)")
        return final
    }

    // MARK: - Internals

    private func composedTranscript() -> String {
        let joined = prefix.isEmpty ? segment : (segment.isEmpty ? prefix : prefix + " " + segment)
        return joined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startEngineTap() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MailError.badResponse("no audio input device")
        }
        let box = requestBox
        input.removeTap(onBus: 0)
        // @Sendable: the tap runs on the audio thread — it must not inherit
        // MainActor isolation (Swift 6 would trap on the executor check).
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            box.request?.append(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    private func beginSegment() {
        guard let recognizer else { return }
        generation += 1
        segmentStartedAt = Date()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.taskHint = .dictation
        request.addsPunctuation = true
        requestBox.request = request
        // @Sendable: Speech invokes this on its own queue — extract plain
        // values there, then hop to the MainActor.
        let currentGeneration = generation
        let handler: @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void = { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorText = error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.handleRecognition(
                    generation: currentGeneration,
                    text: text,
                    isFinal: isFinal,
                    errorText: errorText
                )
            }
        }
        task = recognizer.recognitionTask(with: request, resultHandler: handler)
    }

    private func handleRecognition(generation eventGeneration: Int, text: String?, isFinal: Bool, errorText: String?) {
        // A cancelled task's last callbacks race the segment that replaced
        // it — text from a stale generation would clobber the fresh one.
        guard eventGeneration == generation else { return }
        guard isRecording || phase == .stopping else { return }
        if let text, !text.isEmpty {
            // The on-device recognizer starts over after a pause without any
            // event: the giveaway is a partial unrelated to the current text.
            // Commit what we have before letting the new utterance in.
            let gap = Date().timeIntervalSince(lastPartialAt)
            if !segment.isEmpty,
               Self.looksLikeReset(previous: segment, incoming: text, gapSinceLastPartial: gap) {
                prefix = composedTranscript()
                log.info("segment folded (text reset) chars=\(self.prefix.count, privacy: .public)")
            }
            segment = text
            transcript = composedTranscript()
            instantFailures = 0
            lastPartialAt = Date()
        }
        if let errorText {
            log.info("recognition event: \(errorText, privacy: .public)")
        }

        // The recognizer closes an utterance at every pause (isFinal) and
        // kills the task on errors. Either way: keep what we have and open
        // a fresh segment, so long dictation survives any number of pauses.
        guard isFinal || errorText != nil, phase == .recording else { return }
        if errorText != nil, Date().timeIntervalSince(segmentStartedAt) < 1 {
            instantFailures += 1
            if instantFailures >= 5 {
                // Recognition is refusing to run; restarting forever would
                // spin. Freeze — the text gathered so far survives to stop().
                log.error("recognition keeps failing instantly — no further restarts")
                return
            }
        }
        rollSegment(reason: isFinal ? "pause" : "error")
    }

    /// Is this partial a fresh utterance rather than a revision of the
    /// current one? Compared word-wise — revisions repunctuate and respell
    /// but keep the head words; a reset keeps nothing. Two forms:
    /// - after a gap in the partial stream (revisions arrive in a steady
    ///   flow), any text sharing zero leading words is a reset — this is
    ///   what catches "hello" + short pause + a longer second sentence;
    /// - with no gap, only a shorter, unrelated partial counts, so ordinary
    ///   rewrites ("no" → "know") never fold and duplicate text.
    static func looksLikeReset(
        previous: String,
        incoming: String,
        gapSinceLastPartial: TimeInterval
    ) -> Bool {
        let previousWords = normalizedWords(previous)
        let incomingWords = normalizedWords(incoming)
        guard !previousWords.isEmpty else { return false }
        var common = 0
        for (a, b) in zip(previousWords, incomingWords) {
            guard a == b else { break }
            common += 1
        }
        if gapSinceLastPartial > 0.8, common == 0 {
            return true
        }
        guard incomingWords.count < previousWords.count else { return false }
        return common < max(1, previousWords.count / 4)
    }

    private static func normalizedWords(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// Folds the finished piece into the prefix and starts a new request.
    private func rollSegment(reason: String) {
        prefix = composedTranscript()
        segment = ""
        requestBox.request?.endAudio()
        task?.cancel()
        task = nil
        beginSegment()
        scheduleRestart()
        log.info("segment rolled over (\(reason, privacy: .public)) chars=\(self.prefix.count, privacy: .public)")
    }

    /// Commits the utterance as soon as partials stop flowing — silence means
    /// the recognizer is about to reset, so we beat it to the boundary.
    private func startStallWatcher() {
        stallWatcher?.cancel()
        stallWatcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, self.phase == .recording else { return }
                guard !self.segment.isEmpty,
                      Date().timeIntervalSince(self.lastPartialAt) > Self.stallInterval
                else { continue }
                self.rollSegment(reason: "silence")
            }
        }
    }

    /// Backstop for uninterrupted speech: Apple caps one request at ~1 min,
    /// so roll before the cap even if no pause ever finalizes the segment.
    private func scheduleRestart() {
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(55))
            guard !Task.isCancelled, let self, self.phase == .recording else { return }
            self.rollSegment(reason: "timer")
        }
    }

    // MARK: - Permissions

    /// nonisolated: the TCC callbacks arrive on background queues — an
    /// actor-isolated closure would trap the Swift 6 executor check.
    nonisolated static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speech else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Shared mailbox between the MainActor service and the audio-render tap.
/// The tap only appends buffers; swaps happen on the MainActor. The data
/// race window is benign (a dropped buffer at segment rollover).
final class SpeechRequestBox: @unchecked Sendable {
    var request: SFSpeechAudioBufferRecognitionRequest?
}
