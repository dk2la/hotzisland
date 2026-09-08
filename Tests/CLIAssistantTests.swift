import XCTest

final class CLIAssistantTests: XCTestCase {
    // MARK: - Tool marker protocol

    private func parse(_ text: String) -> CLIToolProtocol.Call? {
        CLIToolProtocol.parse(text)
    }

    func testParsesToolCall() throws {
        let call = try XCTUnwrap(parse("<<TOOL set_timer {\"minutes\": 25}>>"))
        XCTAssertEqual(call.name, "set_timer")
        XCTAssertEqual(call.argumentsJSON, "{\"minutes\": 25}")
    }

    func testParsesLeadingCallWithTrailingChatter() throws {
        // Models often add a sentence despite being told not to; surrounding
        // whitespace and a trailing remark are tolerated.
        let call = try XCTUnwrap(parse("\n<<TOOL create_note {\"text\": \"молоко\"}>>\nDone."))
        XCTAssertEqual(call.name, "create_note")
        let arguments = try JSONSerialization.jsonObject(with: Data(call.argumentsJSON.utf8)) as? [String: Any]
        XCTAssertEqual(arguments?["text"] as? String, "молоко")
    }

    func testRejectsMarkerBuriedInProse() {
        // A marker mid-sentence is quoted content (an email, a note), not a
        // call — accepting it would let any relayed text drive the tools.
        XCTAssertNil(parse("Sure!\n<<TOOL create_note {\"text\": \"молоко\"}>>\nDone."))
        XCTAssertNil(parse("The email says: <<TOOL run_playbook {\"name\": \"Focus\"}>>"))
    }

    func testParsesArgumentlessCall() throws {
        XCTAssertEqual(parse("<<TOOL now_playing {}>>")?.argumentsJSON, "{}")
        // A model that omits the braces entirely still yields a valid call.
        let bare = try XCTUnwrap(parse("<<TOOL today_events>>"))
        XCTAssertEqual(bare.name, "today_events")
        XCTAssertEqual(bare.argumentsJSON, "{}")
    }

    func testPlainAnswersAreNotToolCalls() {
        XCTAssertNil(parse("The timer is set for 25 minutes."))
        XCTAssertNil(parse("Use <<TOOL to call a tool"), "an unterminated marker is not a call")
        XCTAssertNil(parse("<<TOOL >>"), "an empty marker is not a call")
    }

    // MARK: - Binary discovery

    func testLocatesExecutableOnPath() throws {
        // A private PATH with a binary only the test knows about — the
        // runner's own PATH must not decide the outcome.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hotzisland-path-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = "hotzisland-fake-cli"
        let binary = directory.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let searchPath = "/nonexistent-dir:\(directory.path)"

        XCTAssertEqual(CLIAssistantClient.locateExecutable(name, searchPath: searchPath)?.path, binary.path)
        XCTAssertNil(CLIAssistantClient.locateExecutable(name, searchPath: "/nonexistent-dir"))
        XCTAssertNil(CLIAssistantClient.locateExecutable("hotzisland-definitely-not-a-binary", searchPath: searchPath))
    }

    func testProviderShape() {
        XCTAssertEqual(AssistantProvider.claudeCode.executableName, "claude")
        XCTAssertEqual(AssistantProvider.codex.executableName, "codex")
        XCTAssertNil(AssistantProvider.api.executableName)
        XCTAssertTrue(AssistantProvider.claudeCode.isCLI)
        XCTAssertFalse(AssistantProvider.api.isCLI)
    }

    // MARK: - Config migration

    func testConfigStoredBeforeProvidersExistedStillDecodes() throws {
        let legacy = Data("{\"baseURL\":\"https://api.openai.com/v1\",\"model\":\"gpt-5-mini\"}".utf8)
        let config = try JSONDecoder().decode(AssistantConfig.self, from: legacy)
        XCTAssertEqual(config.provider, .api, "old configs must keep working as API configs")
        XCTAssertEqual(config.model, "gpt-5-mini")
    }

    func testConfigRoundTrip() throws {
        let config = AssistantConfig(provider: .claudeCode, baseURL: "", model: "opus")
        let decoded = try JSONDecoder().decode(AssistantConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded, config)
    }

    func testPresetMatching() {
        XCTAssertEqual(AssistantAPIPreset.matching("https://api.perplexity.ai"), .perplexity)
        XCTAssertEqual(AssistantAPIPreset.matching("https://api.anthropic.com/v1/"), .anthropic)
        XCTAssertNil(AssistantAPIPreset.matching("https://example.com/v1"))
    }
}
