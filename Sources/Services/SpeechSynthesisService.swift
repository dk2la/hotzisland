import AVFoundation
import Foundation
import Observation
import OSLog

/// Speaks assistant answers aloud. Deliberately delegate-free: AVFoundation
/// callbacks arriving in an isolated context are this project's known crash
/// class, so `isSpeaking` is polled instead.
@MainActor
@Observable
final class SpeechSynthesisService {
    private(set) var isSpeaking = false

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "speech")

    /// Nothing is written to disk and no network is involved — macOS speaks
    /// locally from the installed voices.
    func speak(_ text: String, locale: Locale) {
        let spoken = Self.strippedForSpeech(text)
        guard !spoken.isEmpty else { return }
        stop()

        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = Self.voice(for: locale)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
        isSpeaking = true
        log.info("speaking chars=\(spoken.count, privacy: .public)")

        watchTask = Task { [weak self] in
            while !Task.isCancelled, self?.synthesizer.isSpeaking == true {
                try? await Task.sleep(for: .milliseconds(250))
            }
            self?.isSpeaking = false
        }
    }

    func stop() {
        watchTask?.cancel()
        watchTask = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    private static func voice(for locale: Locale) -> AVSpeechSynthesisVoice? {
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        return AVSpeechSynthesisVoice(language: identifier)
            ?? AVSpeechSynthesisVoice(language: String(identifier.prefix(2)))
    }

    /// Markdown scaffolding reads badly out loud.
    private static func strippedForSpeech(_ text: String) -> String {
        var spoken = text
        for token in ["**", "__", "`", "#", "⚙"] {
            spoken = spoken.replacingOccurrences(of: token, with: "")
        }
        return spoken.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
