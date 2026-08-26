import Foundation
import OSLog

/// The CLI backends speak plain text, not the tool-call wire format, so tool
/// use rides on a marker the model is asked to emit verbatim. A model that
/// ignores it simply produces a normal chat answer — the degradation is a
/// missing capability, never a broken turn.
enum CLIToolProtocol {
    static let marker = "<<TOOL "

    struct Call: Equatable {
        var name: String
        var argumentsJSON: String
    }

    static let instructions = """
        To act on the widget, reply with ONLY this one line and nothing else:
        <<TOOL tool_name {"arg": "value"}>>
        Available tools:
        - set_timer {"minutes": 25} — start a countdown
        - run_playbook {"name": "Focus"} — run an app workspace
        - now_playing {} — what music is playing
        - today_events {} — today's calendar
        - create_note {"text": "buy milk"} — save a note
        - unread_email_count {} — unread mail count
        You will then receive a TOOL RESULT line; after it, answer the user in \
        prose. Never claim a tool ran unless you saw its TOOL RESULT.
        """

    /// Extracts a call from a model turn, if it emitted one.
    static func parse(_ text: String) -> Call? {
        guard let start = text.range(of: marker),
              let end = text.range(of: ">>", range: start.upperBound..<text.endIndex)
        else { return nil }
        let body = text[start.upperBound..<end.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        guard let split = body.firstIndex(where: { $0 == " " || $0 == "{" }) else {
            return Call(name: body, argumentsJSON: "{}")
        }
        let name = String(body[..<split]).trimmingCharacters(in: .whitespaces)
        let arguments = String(body[split...]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return Call(name: name, argumentsJSON: arguments.isEmpty ? "{}" : arguments)
    }
}

/// Drives a locally installed coding CLI (`claude`, `codex`) as the chat
/// backend, so answers are covered by the user's existing subscription
/// instead of metered API credits.
///
/// Stateless by design: every turn ships the whole (already capped)
/// transcript as one prompt. CLI session resume would save tokens but adds
/// a second failure mode — stale session ids — for a chat this short.
struct CLIAssistantClient: Sendable {
    var provider: AssistantProvider
    /// Optional model override passed to the CLI.
    var model: String

    private static let log = Logger(subsystem: "com.dk2la.hotzisland", category: "assistant")
    private static let timeout: Duration = .seconds(180)

    enum CLIError: Error, LocalizedError {
        case notInstalled(String)
        case failed(String)
        case timedOut
        case emptyOutput

        var errorDescription: String? {
            switch self {
            case .notInstalled(let name): "\(name) CLI not found — install it and sign in"
            case .failed(let message): message
            case .timedOut: "The CLI did not answer in time"
            case .emptyOutput: "The CLI returned nothing"
            }
        }
    }

    // MARK: - Binary discovery

    /// A GUI app launched from Finder inherits a minimal PATH, so the usual
    /// install roots are searched explicitly before giving up.
    static func locateExecutable(_ name: String) -> URL? {
        var roots: [String] = []
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            roots += path.split(separator: ":").map(String.init)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        roots += [
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "\(home)/.volta/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.nvm/versions/node/current/bin",
            "\(home)/.cargo/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
        ]
        let manager = FileManager.default
        for root in roots {
            let candidate = URL(fileURLWithPath: root).appendingPathComponent(name)
            if manager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    var isInstalled: Bool {
        guard let name = provider.executableName else { return false }
        return Self.locateExecutable(name) != nil
    }

    // MARK: - Chat

    /// Runs one turn. `prompt` already contains the flattened transcript.
    func send(system: String, prompt: String) async throws -> String {
        guard let name = provider.executableName,
              let executable = Self.locateExecutable(name)
        else { throw CLIError.notInstalled(provider.executableName ?? "CLI") }

        let arguments: [String]
        switch provider {
        case .claudeCode:
            var flags = [
                "-p", prompt,
                "--output-format", "json",
                "--append-system-prompt", system,
                // The widget is a chat surface: no file edits, no shell.
                "--disallowed-tools", "Bash", "Edit", "Write", "NotebookEdit", "Task",
                // Ignore project CLAUDE.md/hooks/MCP — answers must not
                // depend on whichever directory the app happens to run in.
                "--safe-mode",
            ]
            if !model.isEmpty { flags += ["--model", model] }
            arguments = flags
        case .codex:
            var flags = ["exec", "--json"]
            if !model.isEmpty { flags += ["--model", model] }
            flags.append(system + "\n\n" + prompt)
            arguments = flags
        case .api:
            throw CLIError.notInstalled("CLI")
        }

        let result = try await Self.run(executable: executable, arguments: arguments)
        // Both CLIs write the conversation to disk under the user's home.
        // The widget is an ephemeral surface, so its own trace is removed
        // before the answer is even shown.
        discardStoredTranscript(from: result)
        let text = try parseOutput(result)
        guard !text.isEmpty else { throw CLIError.emptyOutput }
        return text
    }

    /// Probe for the setup form: cheapest possible round-trip.
    func check() async throws -> String {
        try await send(system: "Answer with a single word.", prompt: "Say: ok")
    }

    // MARK: - Leaving no trace

    /// Finds the session id in the CLI's own output and deletes the log it
    /// just wrote. Only the file named after that id is touched, so sessions
    /// the user started themselves are never at risk.
    private func discardStoredTranscript(from result: ProcessResult) {
        guard let id = sessionID(in: result), !id.isEmpty else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots: [URL]
        switch provider {
        case .claudeCode: roots = [home.appendingPathComponent(".claude/projects")]
        case .codex: roots = [home.appendingPathComponent(".codex/sessions")]
        case .api: return
        }
        for root in roots {
            Self.removeFiles(named: id, under: root)
        }
    }

    private func sessionID(in result: ProcessResult) -> String? {
        switch provider {
        case .claudeCode:
            let object = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8))
            return (object as? [String: Any])?["session_id"] as? String
        case .codex:
            for line in result.stdout.split(separator: "\n") {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
                      let json = object as? [String: Any]
                else { continue }
                if let id = (json["thread_id"] ?? json["session_id"]) as? String { return id }
                if let nested = json["item"] as? [String: Any],
                   let id = (nested["thread_id"] ?? nested["session_id"]) as? String { return id }
            }
            return nil
        case .api:
            return nil
        }
    }

    /// Removes every file whose name contains `id` beneath `root`. Both CLIs
    /// shard logs into dated or slugified subfolders, so the id — a UUID —
    /// is the only reliable handle.
    private static func removeFiles(named id: String, under root: URL) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: root.path),
              let walker = manager.enumerator(
                  at: root,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles]
              )
        else { return }
        for case let url as URL in walker where url.lastPathComponent.contains(id) {
            do {
                try manager.removeItem(at: url)
                Self.log.info("discarded cli transcript")
            } catch {
                Self.log.error("could not discard cli transcript: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Output parsing

    private func parseOutput(_ result: ProcessResult) throws -> String {
        switch provider {
        case .claudeCode:
            // `--output-format json` yields one object with `result` holding
            // either the answer or, when is_error is set, the failure text.
            guard let object = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)),
                  let json = object as? [String: Any]
            else {
                guard result.exitCode == 0 else { throw CLIError.failed(Self.failureText(result)) }
                return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let text = (json["result"] as? String) ?? ""
            if (json["is_error"] as? Bool) == true || result.exitCode != 0 {
                throw CLIError.failed(text.isEmpty ? Self.failureText(result) : text)
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)

        case .codex, .api:
            guard result.exitCode == 0 else { throw CLIError.failed(Self.failureText(result)) }
            // Codex streams JSONL events; the answer is the last agent
            // message. Shapes differ between versions, so this walks for a
            // text-bearing agent event and falls back to raw stdout.
            var answer = ""
            for line in result.stdout.split(separator: "\n") {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
                      let json = object as? [String: Any]
                else { continue }
                if let text = Self.agentText(in: json) {
                    answer = text
                }
            }
            if answer.isEmpty {
                answer = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                Self.log.info("codex: no JSON event matched, using raw stdout")
            }
            return answer.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Finds an assistant-authored text payload in one Codex event.
    private static func agentText(in json: [String: Any]) -> String? {
        let type = (json["type"] as? String ?? "").lowercased()
        if type.contains("error"), let message = json["message"] as? String {
            return message
        }
        let item = (json["item"] as? [String: Any]) ?? (json["msg"] as? [String: Any]) ?? json
        let itemType = (item["type"] as? String ?? type).lowercased()
        guard itemType.contains("agent") || itemType.contains("assistant") || itemType.contains("message") else {
            return nil
        }
        if let text = item["text"] as? String, !text.isEmpty { return text }
        if let message = item["message"] as? String, !message.isEmpty { return message }
        if let content = item["content"] as? String, !content.isEmpty { return content }
        if let blocks = item["content"] as? [[String: Any]] {
            let joined = blocks.compactMap { $0["text"] as? String }.joined()
            if !joined.isEmpty { return joined }
        }
        return nil
    }

    private static func failureText(_ result: ProcessResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = stderr.isEmpty ? stdout : stderr
        return detail.isEmpty ? "exit code \(result.exitCode)" : String(detail.prefix(300))
    }

    // MARK: - Process plumbing

    struct ProcessResult: Sendable {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    /// Runs to completion off the main actor, with a hard timeout. No
    /// termination handler: a blocking wait on a detached thread keeps every
    /// Apple callback out of an isolated context.
    private static func run(executable: URL, arguments: [String]) async throws -> ProcessResult {
        let box = ProcessBox()
        return try await withThrowingTaskGroup(of: ProcessResult.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    Thread.detachNewThread {
                        continuation.resume(with: Result { try runBlocking(executable, arguments, box) })
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                box.terminate()
                throw CLIError.timedOut
            }
            guard let first = try await group.next() else { throw CLIError.timedOut }
            group.cancelAll()
            return first
        }
    }

    private static func runBlocking(
        _ executable: URL,
        _ arguments: [String],
        _ box: ProcessBox
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        // Neutral working directory: never inherit a project context.
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["CLAUDE_CODE_ENTRYPOINT"] = "hotzisland"
        process.environment = environment

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        try process.run()
        box.adopt(process)
        // Drain before waiting: a full pipe buffer would deadlock the child.
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        box.release()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    /// Lets the timeout task reach a process the worker thread owns.
    private final class ProcessBox: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?

        func adopt(_ process: Process) {
            lock.lock()
            defer { lock.unlock() }
            self.process = process
        }

        func release() {
            lock.lock()
            defer { lock.unlock() }
            process = nil
        }

        func terminate() {
            lock.lock()
            defer { lock.unlock() }
            process?.terminate()
            process = nil
        }
    }
}
