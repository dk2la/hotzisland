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
    private(set) var lastError: String?

    /// Composer text lives here so collapsing the panel keeps the draft.
    var draft = ""

    /// Voice mode: dictation sends itself, and answers are read aloud.
    private(set) var isVoiceMode = false
    /// The newest assistant answer, if it still needs speaking.
    private(set) var pendingSpeech: String?

    @ObservationIgnored var onEditingChanged: ((Bool) -> Void)?

    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "assistant")
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let keychain = KeychainStore(service: AssistantConfig.keychainService)
    @ObservationIgnored private var cachedKey: String?
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
    private func appendAnswer(_ text: String, isError: Bool = false) {
        transcript.append(AssistantMessage(role: .assistant, text: text, isError: isError))
        if isVoiceMode, !isError {
            pendingSpeech = text
        }
    }

    /// Called once at startup — the playbook store lives outside
    /// ModuleServices, so the toolbox is attached, not constructed here.
    func attachToolbox(services: ModuleServices, playbooks: PlaybookStore) {
        toolbox = AssistantToolbox(services: services, playbooks: playbooks)
    }

    // MARK: - Configuration

    func saveConfig(_ newConfig: AssistantConfig, key: String) {
        do {
            try keychain.setPassword(key, account: Self.keyAccount)
        } catch {
            lastError = "Keychain: \(error.localizedDescription)"
            return
        }
        cachedKey = key
        config = newConfig
        if let data = try? JSONEncoder().encode(newConfig) {
            defaults.set(data, forKey: AssistantConfig.defaultsKey)
        }
        lastError = nil
        log.info("assistant saved model=\(newConfig.model, privacy: .public)")
    }

    func removeConfig() {
        try? keychain.deletePassword(account: Self.keyAccount)
        cachedKey = nil
        config = nil
        defaults.removeObject(forKey: AssistantConfig.defaultsKey)
        transcript = []
        apiHistory = []
        lastError = nil
        log.info("assistant removed")
    }

    func clearTranscript() {
        transcript = []
        apiHistory = []
        lastError = nil
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
        lastError = nil
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
                lastError = error.localizedDescription
                transcript.append(AssistantMessage(role: .assistant, text: error.localizedDescription, isError: true))
                log.error("assistant cli failed: \(error.localizedDescription, privacy: .public)")
                return
            }

            guard let call = CLIToolProtocol.parse(answer) else {
                appendAnswer(answer)
                return
            }
            let label = AssistantToolbox.label(name: call.name, argumentsJSON: call.argumentsJSON)
            let result = toolbox?.execute(name: call.name, argumentsJSON: call.argumentsJSON)
                ?? "Error: tools are unavailable."
            transcript.append(AssistantMessage(
                role: .tool,
                text: result,
                toolLabel: label,
                isError: result.hasPrefix("Error")
            ))
        }
        transcript.append(AssistantMessage(role: .assistant, text: "…", isError: true))
        log.error("assistant hit tool round limit")
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

    private func cliSystemPrompt() -> String {
        """
        You are the assistant inside HotzIsland, a macOS desktop widget with modules: \
        timer, playbooks (app workspaces), music, calendar, notes and email. \
        Be brief — answers render in a small panel. Reply in \(L10n.shared.language.title).

        \(CLIToolProtocol.instructions)
        """
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
                lastError = error.localizedDescription
                transcript.append(AssistantMessage(role: .assistant, text: error.localizedDescription, isError: true))
                log.error("assistant request failed: \(error.localizedDescription, privacy: .public)")
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
                let label = AssistantToolbox.label(name: call.name, argumentsJSON: call.argumentsJSON)
                let result = toolbox?.execute(name: call.name, argumentsJSON: call.argumentsJSON)
                    ?? "Error: tools are unavailable."
                transcript.append(AssistantMessage(
                    role: .tool,
                    text: result,
                    toolLabel: label,
                    isError: result.hasPrefix("Error")
                ))
                apiHistory.append([
                    "role": "tool",
                    "tool_call_id": call.id,
                    "content": result,
                ])
            }
            trimHistory()
        }
        // Tool-round budget exhausted — surface whatever state we're in.
        transcript.append(AssistantMessage(role: .assistant, text: "…", isError: true))
        log.error("assistant hit tool round limit")
    }

    private func systemMessage() -> [String: Any & Sendable] {
        let language = L10n.shared.language.title
        return [
            "role": "system",
            "content": """
            You are the assistant inside HotzIsland, a macOS desktop widget with modules: \
            timer, playbooks (app workspaces), music, calendar, notes and email. \
            Use the provided tools to act on the user's widget when asked; do not invent tool results. \
            Be brief — answers render in a small panel. Reply in \(language).
            """,
        ]
    }

    private func apiKey() -> String {
        if let cachedKey { return cachedKey }
        let stored = (try? keychain.password(account: Self.keyAccount)) ?? ""
        cachedKey = stored
        return stored
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
