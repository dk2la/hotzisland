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

    private var spec: (title: String, executableName: String?) {
        switch self {
        case .claudeCode: ("Claude", "claude")
        case .codex: ("ChatGPT", "codex")
        case .api: ("API", nil)
        }
    }

    var title: String { spec.title }
    /// Name of the command-line tool this provider drives, if any.
    var executableName: String? { spec.executableName }

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

    private var spec: (title: String, baseURL: String, sampleModel: String) {
        switch self {
        case .openai: ("OpenAI", "https://api.openai.com/v1", "gpt-5-mini")
        case .anthropic: ("Anthropic", "https://api.anthropic.com/v1", "claude-opus-5")
        case .openrouter: ("OpenRouter", "https://openrouter.ai/api/v1", "anthropic/claude-opus-5")
        case .perplexity: ("Perplexity", "https://api.perplexity.ai", "sonar-pro")
        case .ollama: ("Ollama", "http://localhost:11434/v1", "llama3.2")
        }
    }

    var title: String { spec.title }
    var baseURL: String { spec.baseURL }
    var sampleModel: String { spec.sampleModel }

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
