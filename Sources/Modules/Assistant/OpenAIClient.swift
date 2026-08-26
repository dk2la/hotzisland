import Foundation

/// Thin non-streaming client for the de-facto standard `/chat/completions`
/// endpoint. Payloads are built with JSONSerialization on purpose: tool
/// schemas are free-form JSON, and providers (OpenAI, OpenRouter, Ollama,
/// LiteLLM) differ in which optional fields they include — a tolerant
/// dictionary walk survives all of them. SSE streaming: future iteration.
struct OpenAIClient: Sendable {
    var baseURL: String
    /// Empty = no Authorization header (local Ollama).
    var apiKey: String
    var model: String

    struct Reply: Sendable {
        var text: String
        var toolCalls: [ToolCall]
    }

    struct ToolCall: Sendable {
        var id: String
        var name: String
        var argumentsJSON: String
    }

    enum ClientError: Error, LocalizedError {
        case badURL
        case server(String)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .badURL: "Invalid base URL"
            case .server(let message): message
            case .malformedResponse: "Unexpected response shape"
            }
        }
    }

    /// `messages` are wire-shaped dicts (role/content/tool_calls/…) so the
    /// caller can round-trip tool plumbing untouched.
    func complete(
        messages: [[String: Any & Sendable]],
        tools: [[String: Any & Sendable]] = []
    ) async throws -> Reply {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: trimmed + "/chat/completions"), url.scheme != nil else {
            throw ClientError.badURL
        }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        var body: [String: Any] = ["model": model, "messages": messages]
        if !tools.isEmpty {
            body["tools"] = tools
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(status) else {
            throw ClientError.server(Self.errorText(json, data: data, status: status))
        }
        return try Self.parseReply(json)
    }

    /// Pulls text + tool calls out of a completed response body. Static and
    /// pure — unit-tested against OpenAI- and Ollama-shaped fixtures.
    static func parseReply(_ json: [String: Any]?) throws -> Reply {
        guard let message = ((json?["choices"] as? [[String: Any]])?.first?["message"]) as? [String: Any] else {
            throw ClientError.malformedResponse
        }
        var calls: [ToolCall] = []
        for (index, raw) in ((message["tool_calls"] as? [[String: Any]]) ?? []).enumerated() {
            guard let function = raw["function"] as? [String: Any],
                  let name = function["name"] as? String
            else { continue }
            // Ollama sends arguments as an object; OpenAI as a JSON string.
            let argumentsJSON: String
            if let text = function["arguments"] as? String {
                argumentsJSON = text
            } else if let object = function["arguments"],
                      let encoded = try? JSONSerialization.data(withJSONObject: object) {
                argumentsJSON = String(decoding: encoded, as: UTF8.self)
            } else {
                argumentsJSON = "{}"
            }
            calls.append(ToolCall(
                id: raw["id"] as? String ?? "call_\(index)",
                name: name,
                argumentsJSON: argumentsJSON
            ))
        }
        return Reply(text: message["content"] as? String ?? "", toolCalls: calls)
    }

    static func errorText(_ json: [String: Any]?, data: Data, status: Int) -> String {
        if let message = (json?["error"] as? [String: Any])?["message"] as? String {
            return message
        }
        let snippet = String(decoding: data.prefix(200), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return snippet.isEmpty ? "HTTP \(status)" : "HTTP \(status): \(snippet)"
    }
}
