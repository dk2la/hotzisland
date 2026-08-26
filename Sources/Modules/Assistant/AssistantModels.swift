import Foundation

/// Where the assistant's answers come from. The two CLI backends spend the
/// user's existing chat subscription instead of metered API credits.
enum AssistantProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Local `claude` CLI — covered by a Claude Pro/Max subscription.
    case claudeCode
    /// Local `codex` CLI — covered by a ChatGPT Plus/Pro subscription.
    case codex
    /// Any OpenAI-compatible HTTP endpoint, billed per token.
    case api

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claudeCode: "Claude"
        case .codex: "ChatGPT"
        case .api: "API"
        }
    }

    /// Name of the command-line tool this provider drives, if any.
    var executableName: String? {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .api: nil
        }
    }

    var isCLI: Bool { executableName != nil }
}

/// Assistant provider configuration. Non-secret parts live in UserDefaults;
/// the API key lives in the Keychain.
struct AssistantConfig: Codable, Equatable {
    var provider: AssistantProvider
    var baseURL: String
    var model: String

    static let defaultsKey = "assistant.config.v1"
    static let keychainService = "com.dk2la.hotzisland.assistant"
    static let defaultBaseURL = "https://api.openai.com/v1"

    init(provider: AssistantProvider = .api, baseURL: String = defaultBaseURL, model: String = "") {
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
    }

    /// Hand-written so configs stored before providers existed still decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(AssistantProvider.self, forKey: .provider) ?? .api
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? Self.defaultBaseURL
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
    }
}

/// Endpoint presets for the API provider — the hosts people actually use.
enum AssistantAPIPreset: String, CaseIterable, Identifiable {
    case openai
    case anthropic
    case openrouter
    case perplexity
    case ollama

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        case .openrouter: "OpenRouter"
        case .perplexity: "Perplexity"
        case .ollama: "Ollama"
        }
    }

    var baseURL: String {
        switch self {
        case .openai: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com/v1"
        case .openrouter: "https://openrouter.ai/api/v1"
        case .perplexity: "https://api.perplexity.ai"
        case .ollama: "http://localhost:11434/v1"
        }
    }

    var sampleModel: String {
        switch self {
        case .openai: "gpt-5-mini"
        case .anthropic: "claude-opus-5"
        case .openrouter: "anthropic/claude-opus-5"
        case .perplexity: "sonar-pro"
        case .ollama: "llama3.2"
        }
    }

    static func matching(_ baseURL: String) -> AssistantAPIPreset? {
        let normalized = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return allCases.first { $0.baseURL == normalized }
    }
}

/// One transcript entry. Tool rows render as a mono "⚙ set_timer(25)" line
/// between the user's request and the assistant's summary.
struct AssistantMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
        case tool
    }

    let id = UUID()
    var role: Role
    var text: String
    /// For `.tool` rows: the rendered call, e.g. "set_timer(25)".
    var toolLabel: String?
    var isError = false
}
