import Foundation

/// Scripted stand-in for `TLSTransport`: hands out server replies in order
/// and records every command the client writes. A `readLine` on an empty
/// script behaves like a dropped socket (`MailError.connectionClosed`).
actor FakeMailTransport: MailLineTransport {
    enum Reply {
        /// One CRLF-terminated line (terminator appended here).
        case line(String)
        /// Raw literal payload, served only by `read(exactly:)`.
        case bytes(Data)
        /// Error thrown by the next read.
        case fail(MailError)
    }

    enum ScriptError: Error {
        case unexpectedRead(String)
    }

    private var script: [Reply] = []
    /// Commands written by the client, one entry per `send`, CRLF stripped.
    private(set) var written: [String] = []
    private(set) var connectCount = 0
    private(set) var closeCount = 0
    /// Every `read(exactly:)` request, in order.
    private(set) var literalReads: [Int] = []

    // MARK: - Scripting

    func enqueue(_ reply: Reply) {
        script.append(reply)
    }

    func enqueueLine(_ line: String) {
        script.append(.line(line))
    }

    func enqueueLiteral(_ data: Data) {
        script.append(.bytes(data))
    }

    func enqueueFailure(_ error: MailError) {
        script.append(.fail(error))
    }

    /// The "* OK" banner the client expects right after `connect`.
    func enqueueGreeting() {
        script.append(.line("* OK IMAP4rev1 ready"))
    }

    /// A full reply to the command that will carry `tag`: untagged lines
    /// first, then the tagged completion. `IMAPClient` numbers tags
    /// "A1", "A2", … in the order commands are sent.
    func enqueueResponse(tag: String, untagged: [String] = [], status: String = "OK done") {
        for line in untagged {
            script.append(.line(line))
        }
        script.append(.line("\(tag) \(status)"))
    }

    // MARK: - MailLineTransport

    func connect() async throws {
        connectCount += 1
    }

    func send(_ data: Data) async throws {
        // Strip the terminator on bytes: to String, "\r\n" is one grapheme.
        var bytes = data
        while let last = bytes.last, last == 13 || last == 10 {
            bytes.removeLast()
        }
        written.append(String(decoding: bytes, as: UTF8.self))
    }

    func readLine(timeout: Duration) async throws -> Data {
        guard !script.isEmpty else { throw MailError.connectionClosed }
        switch script.removeFirst() {
        case .line(let line):
            return Data((line + "\r\n").utf8)
        case .bytes:
            throw ScriptError.unexpectedRead("readLine hit a literal payload")
        case .fail(let error):
            throw error
        }
    }

    func read(exactly count: Int) async throws -> Data {
        literalReads.append(count)
        guard !script.isEmpty else { throw MailError.connectionClosed }
        switch script.removeFirst() {
        case .bytes(let data):
            guard data.count == count else {
                throw ScriptError.unexpectedRead("literal is \(data.count) bytes, client asked for \(count)")
            }
            return data
        case .line(let line):
            throw ScriptError.unexpectedRead("read(exactly:) hit line \(line)")
        case .fail(let error):
            throw error
        }
    }

    func close() async {
        closeCount += 1
    }
}
