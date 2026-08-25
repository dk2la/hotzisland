import AppKit
import AVFoundation
import Foundation
import Observation
import OSLog
import Speech

/// Dictation: microphone → live transcript. Owned by ModuleServices so any
/// module (Notes now, the assistant later) can borrow the same recorder.
///
/// Apple caps a single recognition request at ~1 minute, so the service
/// restarts the request every 55 s, folding the finished segment into a
/// prefix — the visible transcript never loses text mid-dictation.
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
        log.info("recording locale=\(locale.identifier, privacy: .public) onDevice=\(recognizer.supportsOnDeviceRecognition, privacy: .public)")
    }

    /// Stops the engine and returns the final transcript.
    func stop() async -> String {
        guard isRecording else { return "" }
        phase = .stopping
        restartTask?.cancel()
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
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        requestBox.request = request
        // @Sendable: Speech invokes this on its own queue — extract plain
        // values there, then hop to the MainActor.
        let handler: @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void = { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let errorText = error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.handleRecognition(text: text, errorText: errorText)
            }
        }
        task = recognizer.recognitionTask(with: request, resultHandler: handler)
    }

    private func handleRecognition(text: String?, errorText: String?) {
        guard isRecording || phase == .stopping else { return }
        if let text {
            segment = text
            transcript = composedTranscript()
        }
        if let errorText {
            // Cancellation between segments is routine; anything else is
            // worth a log line but must not kill the dictation.
            log.info("recognition event: \(errorText, privacy: .public)")
        }
    }

    /// Rolls to a fresh recognition request before Apple's ~1 min cap.
    private func scheduleRestart() {
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(55))
            guard !Task.isCancelled, let self, self.phase == .recording else { return }
            self.prefix = self.composedTranscript()
            self.segment = ""
            self.requestBox.request?.endAudio()
            self.task?.cancel()
            self.beginSegment()
            self.scheduleRestart()
            self.log.info("segment rolled over")
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
