import XCTest

final class OpenAIClientTests: XCTestCase {
    private func json(_ text: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }

    func testPlainTextReply() throws {
        let reply = try OpenAIClient.parseReply(json("""
        {"choices": [{"message": {"role": "assistant", "content": "Привет!"}}]}
        """))
        XCTAssertEqual(reply.text, "Привет!")
        XCTAssertTrue(reply.toolCalls.isEmpty)
    }

    /// OpenAI/OpenRouter shape: arguments arrive as a JSON *string*.
    func testOpenAIStyleToolCall() throws {
        let reply = try OpenAIClient.parseReply(json("""
        {"choices": [{"message": {"role": "assistant", "content": null, "tool_calls": [
            {"id": "call_abc", "type": "function",
             "function": {"name": "set_timer", "arguments": "{\\"minutes\\": 25}"}}
        ]}}]}
        """))
        XCTAssertEqual(reply.text, "")
        XCTAssertEqual(reply.toolCalls.count, 1)
        XCTAssertEqual(reply.toolCalls[0].id, "call_abc")
        XCTAssertEqual(reply.toolCalls[0].name, "set_timer")
        XCTAssertEqual(reply.toolCalls[0].argumentsJSON, "{\"minutes\": 25}")
    }

    /// Ollama shape: arguments arrive as an *object*, and ids are omitted.
    func testOllamaStyleToolCall() throws {
        let reply = try OpenAIClient.parseReply(json("""
        {"choices": [{"message": {"role": "assistant", "content": "", "tool_calls": [
            {"function": {"name": "create_note", "arguments": {"text": "молоко"}}}
        ]}}]}
        """))
        XCTAssertEqual(reply.toolCalls.count, 1)
        XCTAssertEqual(reply.toolCalls[0].id, "call_0", "missing ids get a stable synthetic one")
        let arguments = json(reply.toolCalls[0].argumentsJSON)
        XCTAssertEqual(arguments?["text"] as? String, "молоко")
    }

    func testMalformedResponseThrows() {
        XCTAssertThrowsError(try OpenAIClient.parseReply(json("{\"unexpected\": true}")))
        XCTAssertThrowsError(try OpenAIClient.parseReply(nil))
    }

    func testErrorTextPrefersProviderMessage() {
        let body = json("{\"error\": {\"message\": \"Invalid API key\", \"code\": 401}}")
        XCTAssertEqual(OpenAIClient.errorText(body, data: Data(), status: 401), "Invalid API key")
        // Non-JSON body falls back to a trimmed snippet with the status.
        XCTAssertEqual(
            OpenAIClient.errorText(nil, data: Data("upstream busy".utf8), status: 502),
            "HTTP 502: upstream busy"
        )
        XCTAssertEqual(OpenAIClient.errorText(nil, data: Data(), status: 500), "HTTP 500")
    }
}
