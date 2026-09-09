import XCTest

/// `MailSession` ordering and retry rules, driven through fake transports.
final class MailSessionTests: XCTestCase {
    /// Hands out pre-scripted transports in order and counts how many the
    /// session asked for. Synchronous because the factory closure is.
    private final class TransportFactory: @unchecked Sendable {
        private let lock = NSLock()
        private var pending: [FakeMailTransport]
        private(set) var created = 0

        init(_ transports: [FakeMailTransport]) {
            pending = transports
        }

        func make(_ host: String, _ port: UInt16) -> any MailLineTransport {
            lock.lock()
            defer { lock.unlock() }
            created += 1
            guard !pending.isEmpty else {
                XCTFail("session asked for more transports than the test scripted")
                return FakeMailTransport()
            }
            return pending.removeFirst()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return created
        }
    }

    private actor Recorder {
        private(set) var events: [String] = []
        func add(_ event: String) { events.append(event) }
    }

    /// Blocks `wait()` callers until `open()`.
    private actor Gate {
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var isOpen = false

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            let released = waiters
            waiters.removeAll()
            released.forEach { $0.resume() }
        }
    }

    /// Greeting, LOGIN and SELECT — what `open()` needs on a fresh socket.
    /// Tags start at A1 because every transport gets its own client.
    private func scriptOpen(_ transport: FakeMailTransport, exists: Int = 1) async {
        await transport.enqueueGreeting()
        await transport.enqueueResponse(tag: "A1", status: "OK LOGIN completed")
        await transport.enqueueResponse(tag: "A2", untagged: ["* \(exists) EXISTS"], status: "OK SELECT completed")
    }

    private func makeSession(_ factory: TransportFactory) -> MailSession {
        MailSession(host: "imap.example.com", port: 993, user: "u", password: "p") { host, port in
            factory.make(host, port)
        }
    }

    private func waitUntil(_ condition: @escaping @Sendable () async -> Bool) async {
        for _ in 0..<400 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - Ordering

    func testConcurrentRunsExecuteStrictlyOneAfterAnother() async throws {
        let transport = FakeMailTransport()
        await scriptOpen(transport)
        let factory = TransportFactory([transport])
        let session = makeSession(factory)
        let recorder = Recorder()
        let gate = Gate()

        let first = Task {
            try await session.run { _ in
                await recorder.add("first-start")
                await gate.wait()
                await recorder.add("first-end")
            }
        }
        // Only queue the second once the first body is provably running.
        await waitUntil { await recorder.events == ["first-start"] }
        let second = Task {
            try await session.run { _ in
                await recorder.add("second-start")
                await recorder.add("second-end")
            }
        }
        // Nothing holds the second body back except the chain; give it
        // ample time to misbehave.
        try await Task.sleep(for: .milliseconds(100))
        let midway = await recorder.events
        XCTAssertEqual(midway, ["first-start"], "second run must not start while the first is in flight")

        await gate.open()
        try await first.value
        try await second.value

        let events = await recorder.events
        XCTAssertEqual(events, ["first-start", "first-end", "second-start", "second-end"])
        XCTAssertEqual(factory.count, 1, "the second run reuses the live connection")
    }

    // MARK: - Retry

    func testRetriesOnceOnTransportFailureWithAFreshTransport() async throws {
        let stale = FakeMailTransport()
        await scriptOpen(stale)
        // The body's SELECT times out on the stale socket…
        await stale.enqueueFailure(.timeout)
        let fresh = FakeMailTransport()
        await scriptOpen(fresh, exists: 12)
        // …and succeeds on the reconnected one.
        await fresh.enqueueResponse(tag: "A3", untagged: ["* 12 EXISTS"], status: "OK SELECT completed")
        let factory = TransportFactory([stale, fresh])
        let session = makeSession(factory)

        let exists = try await session.run { try await $0.selectInbox() }

        XCTAssertEqual(exists, 12)
        XCTAssertEqual(factory.count, 2, "retry must reconnect, not reuse the dead socket")
        let staleWritten = await stale.written
        XCTAssertEqual(staleWritten, ["A1 LOGIN \"u\" \"p\"", "A2 SELECT INBOX", "A3 SELECT INBOX", "A4 LOGOUT"])
        let staleClosed = await stale.closeCount
        XCTAssertEqual(staleClosed, 1)
        let freshWritten = await fresh.written
        XCTAssertEqual(freshWritten, ["A1 LOGIN \"u\" \"p\"", "A2 SELECT INBOX", "A3 SELECT INBOX"])
    }

    func testRetriesOnceOnConnectionClosed() async throws {
        let stale = FakeMailTransport()
        await scriptOpen(stale)
        // No reply scripted: the body's NOOP finds the socket gone.
        let fresh = FakeMailTransport()
        await scriptOpen(fresh)
        await fresh.enqueueResponse(tag: "A3", status: "OK NOOP completed")
        let factory = TransportFactory([stale, fresh])
        let session = makeSession(factory)

        try await session.run { try await $0.ping() }

        XCTAssertEqual(factory.count, 2)
        let freshWritten = await fresh.written
        XCTAssertEqual(freshWritten.last, "A3 NOOP")
    }

    func testDoesNotRetryOnAuthFailure() async throws {
        let transport = FakeMailTransport()
        await transport.enqueueGreeting()
        await transport.enqueueResponse(tag: "A1", status: "NO [AUTHENTICATIONFAILED] Invalid credentials")
        let factory = TransportFactory([transport])
        let session = makeSession(factory)

        do {
            try await session.run { _ in }
            XCTFail("expected authFailed")
        } catch let MailError.authFailed(message) {
            XCTAssertEqual(message, "NO [AUTHENTICATIONFAILED] Invalid credentials")
        }
        XCTAssertEqual(factory.count, 1, "a rejected LOGIN would fail identically — never retried")
    }

    func testDoesNotRetryOnBadResponse() async throws {
        let transport = FakeMailTransport()
        await scriptOpen(transport)
        await transport.enqueueResponse(tag: "A3", status: "NO [CANNOT] Mailbox does not exist")
        let factory = TransportFactory([transport])
        let session = makeSession(factory)

        do {
            try await session.run { try await $0.move(uid: 9, to: "Archive") }
            XCTFail("expected badResponse")
        } catch let MailError.badResponse(message) {
            XCTAssertEqual(message, "NO [CANNOT] Mailbox does not exist")
        }
        XCTAssertEqual(factory.count, 1, "a NO/BAD is a protocol answer, and a repeated MOVE could act twice")
        let written = await transport.written
        XCTAssertEqual(written.last, "A3 UID MOVE 9 \"Archive\"")
    }
}
