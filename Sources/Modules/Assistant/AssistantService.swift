import Foundation
import Observation
import OSLog

/// "Assistant" module service: chat with any OpenAI-compatible model, with
/// tool-calling into the widget's own modules. One request loop per user
/// message; tool rounds are capped so a confused model cannot spin forever.
@MainActor
@Observable
final class AssistantService {
    private(set) var config: AssistantConfig?
    private(set) var transcript: [AssistantMessage] = []
    private(set) var isThinking = false

    /// Composer text lives here so collapsing the panel keeps the draft.
    var draft = ""

    /// Voice mode: dictation sends itself, and answers are read aloud.
    private(set) var isVoiceMode = false
    /// The newest assistant answer, if it still needs speaking.
    private(set) var pendingSpeech: String?

    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "assistant")
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let vault = SecretVault(service: AssistantConfig.keychainService)
    @ObservationIgnored private var toolbox: AssistantToolbox?
    /// Wire-shaped history (role/content/tool_calls dicts) sent to the API.
    @ObservationIgnored private var apiHistory: [[String: Any & Sendable]] = []

    private static let keyAccount = "api-key"
    private static let maxToolRounds = 5
    private static let historyLimit = 40
    private static let voiceModeKey = "assistant.voiceMode"

    init() {
        if let data = defaults.data(forKey: AssistantConfig.defaultsKey),
           let stored = try? JSONDecoder().decode(AssistantConfig.self, from: data) {
            config = stored
        }
        isVoiceMode = defaults.bool(forKey: Self.voiceModeKey)
        log.info("assistant configured=\(self.config != nil, privacy: .public)")
    }

    // MARK: - Voice mode

    func setVoiceMode(_ enabled: Bool) {
        isVoiceMode = enabled
        defaults.set(enabled, forKey: Self.voiceModeKey)
    }

    /// Handed to the synthesizer by the view, then cleared so a redraw does
    /// not speak the same answer twice.
    func consumePendingSpeech() -> String? {
        defer { pendingSpeech = nil }
        return pendingSpeech
    }

    /// Dictation finished: in voice mode the turn sends itself.
    func acceptDictation(_ text: String) {
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return }
        draft = draft.isEmpty ? spoken : draft + " " + spoken
        if isVoiceMode {
            send()
        }
    }

    /// Appends an answer and, in voice mode, queues it to be read aloud.
    private func appendAnswer(_ text: String) {
        transcript.append(AssistantMessage(role: .assistant, text: text))
        if isVoiceMode {
            pendingSpeech = text
        }
    }

    /// Request failures render as error rows in the transcript — there is no
    /// separate error surface.
    private func appendFailure(_ message: String) {
        transcript.append(AssistantMessage(role: .assistant, text: message, isError: true))
        log.error("assistant turn failed: \(message, privacy: .public)")
    }

    /// Runs one tool call, records it in the transcript, and returns the
    /// outcome for the backend to feed back to the model.
    private func performToolCall(name: String, argumentsJSON: String) -> ToolOutcome {
        let outcome = toolbox?.execute(name: name, argumentsJSON: argumentsJSON)
            ?? .failure("Tools are unavailable.")
        transcript.append(AssistantMessage(
            role: .tool,
            text: outcome.text,
            toolLabel: AssistantToolbox.label(name: name, argumentsJSON: argumentsJSON),
            isError: outcome.isError
        ))
        return outcome
    }

    private func appendRoundLimitTail() {
        appendFailure("…")
        log.error("assistant hit tool round limit")
    }

    /// Called by ModuleServices at the end of its init — the toolbox needs
    /// the fully built service container, so it cannot exist in our own init.
    func attachToolbox(services: ModuleServices, playbooks: PlaybookStore) {
        toolbox = AssistantToolbox(services: services, playbooks: playbooks)
    }

    // MARK: - Configuration

    func saveConfig(_ newConfig: AssistantConfig, key: String) {
        do {
            try vault.set(key, account: Self.keyAccount)
        } catch {
            log.error("keychain save failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        config = newConfig
        if let data = try? JSONEncoder().encode(newConfig) {
            defaults.set(data, forKey: AssistantConfig.defaultsKey)
        }
        log.info("assistant saved model=\(newConfig.model, privacy: .public)")
    }

    func removeConfig() {
        vault.delete(account: Self.keyAccount)
        config = nil
        defaults.removeObject(forKey: AssistantConfig.defaultsKey)
        transcript = []
        apiHistory = []
        log.info("assistant removed")
    }

    func clearTranscript() {
        transcript = []
        apiHistory = []
    }

    /// Setup-form probe: one tiny round-trip proves the whole path.
    nonisolated static func testConnection(
        _ config: AssistantConfig,
        key: String
    ) async -> Result<Void, Error> {
        do {
            if config.provider.isCLI {
                let client = CLIAssistantClient(provider: config.provider, model: config.model)
                _ = try await client.check()
            } else {
                let client = OpenAIClient(baseURL: config.baseURL, apiKey: key, model: config.model)
                _ = try await client.complete(messages: [
                    ["role": "user", "content": "Reply with the single word: ok"],
                ])
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Chat

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking, let config else { return }
        draft = ""
        transcript.append(AssistantMessage(role: .user, text: text))
        apiHistory.append(["role": "user", "content": text])
        trimHistory()

        isThinking = true
        if config.provider.isCLI {
            let client = CLIAssistantClient(provider: config.provider, model: config.model)
            Task { [weak self] in
                await self?.runCLILoop(client: client)
                self?.isThinking = false
            }
        } else {
            let client = OpenAIClient(baseURL: config.baseURL, apiKey: apiKey(), model: config.model)
            Task { [weak self] in
                await self?.runLoop(client: client)
                self?.isThinking = false
            }
        }
    }

    /// CLI backends get the transcript as plain text and answer in prose;
    /// tool use rides on the marker protocol. Same round cap as the API path.
    private func runCLILoop(client: CLIAssistantClient) async {
        for _ in 0..<Self.maxToolRounds {
            let answer: String
            do {
                answer = try await client.send(system: cliSystemPrompt(), prompt: cliPrompt())
            } catch {
                appendFailure(error.localizedDescription)
                return
            }

            guard let call = CLIToolProtocol.parse(answer) else {
                appendAnswer(answer)
                return
            }
            _ = performToolCall(name: call.name, argumentsJSON: call.argumentsJSON)
        }
        appendRoundLimitTail()
    }

    /// The visible transcript, flattened for a CLI that takes one prompt.
    private func cliPrompt() -> String {
        transcript.suffix(Self.historyLimit).compactMap { message in
            switch message.role {
            case .user: "User: \(message.text)"
            case .assistant: message.isError ? nil : "Assistant: \(message.text)"
            case .tool: "TOOL RESULT \(message.toolLabel ?? ""): \(message.text)"
            }
        }
        .joined(separator: "\n\n")
    }

    /// The one description of who the assistant is; each backend appends its
    /// own tool-usage contract.
    private func basePrompt() -> String {
        """
        You are the assistant inside HotzIsland, a macOS desktop widget with modules: \
        timer, playbooks (app workspaces), music, calendar, notes and email. \
        Be brief — answers render in a small panel. Reply in \(L10n.shared.language.title).
        """
    }

    private func cliSystemPrompt() -> String {
        basePrompt() + "\n\n" + AssistantToolbox.cliInstructions
    }

    private func runLoop(client: OpenAIClient) async {
        for _ in 0..<Self.maxToolRounds {
            let reply: OpenAIClient.Reply
            do {
                reply = try await client.complete(
                    messages: [systemMessage()] + apiHistory,
                    tools: AssistantToolbox.declarations
                )
            } catch {
                appendFailure(error.localizedDescription)
                return
            }

            guard !reply.toolCalls.isEmpty else {
                let text = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
                appendAnswer(text.isEmpty ? "…" : text)
                apiHistory.append(["role": "assistant", "content": reply.text])
                trimHistory()
                return
            }

            // Echo the assistant turn with its tool calls, then execute each
            // and feed the results back — the wire shape providers expect.
            let toolCallDicts: [[String: Any & Sendable]] = reply.toolCalls.map { call in
                let function: [String: String] = ["name": call.name, "arguments": call.argumentsJSON]
                return ["id": call.id, "type": "function", "function": function]
            }
            apiHistory.append([
                "role": "assistant",
                "content": reply.text,
                "tool_calls": toolCallDicts,
            ])
            for call in reply.toolCalls {
                let outcome = performToolCall(name: call.name, argumentsJSON: call.argumentsJSON)
                apiHistory.append([
                    "role": "tool",
                    "tool_call_id": call.id,
                    "content": outcome.text,
                ])
            }
            trimHistory()
        }
        appendRoundLimitTail()
    }

    private func systemMessage() -> [String: Any & Sendable] {
        [
            "role": "system",
            "content": basePrompt()
                + " Use the provided tools to act on the user's widget when asked; do not invent tool results.",
        ]
    }

    private func apiKey() -> String {
        vault.secret(account: Self.keyAccount) ?? ""
    }

    /// Bounds the wire history. Trimming never starts on a tool message —
    /// a tool result without its assistant tool_calls turn breaks providers.
    private func trimHistory() {
        guard apiHistory.count > Self.historyLimit else { return }
        var trimmed = Array(apiHistory.suffix(Self.historyLimit))
        while let first = trimmed.first, first["role"] as? String == "tool" {
            trimmed.removeFirst()
        }
        apiHistory = trimmed
    }
}
