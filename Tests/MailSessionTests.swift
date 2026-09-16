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
    private func scriptOpen(
        _ transport: FakeMailTransport,
        exists: Int = 1,
        capabilities: String? = nil
    ) async {
        await transport.enqueueGreeting(capabilities: capabilities)
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

    // MARK: - Mailboxes

    /// `run(in:)` sends SELECT only when the connection has another
    /// mailbox open: INBOX right after opening costs nothing, a second
    /// command in the same folder costs nothing either.
    func testRunInMailboxSelectsOnlyWhenItDiffers() async throws {
        let transport = FakeMailTransport()
        await scriptOpen(transport)
        await transport.enqueueResponse(tag: "A3", status: "OK NOOP completed")
        await transport.enqueueResponse(tag: "A4", untagged: ["* 3 EXISTS"], status: "OK SELECT completed")
        await transport.enqueueResponse(tag: "A5", status: "OK NOOP completed")
        await transport.enqueueResponse(tag: "A6", status: "OK NOOP completed")
        await transport.enqueueResponse(tag: "A7", untagged: ["* 1 EXISTS"], status: "OK SELECT completed")
        await transport.enqueueResponse(tag: "A8", status: "OK NOOP completed")
        let factory = TransportFactory([transport])
        let session = makeSession(factory)

        try await session.run(in: "INBOX") { try await $0.ping() }
        try await session.run(in: "[Gmail]/Sent Mail") { try await $0.ping() }
        try await session.run(in: "[Gmail]/Sent Mail") { try await $0.ping() }
        try await session.run(in: "INBOX") { try await $0.ping() }

        let written = await transport.written
        XCTAssertEqual(written, [
            "A1 LOGIN \"u\" \"p\"",
            "A2 SELECT INBOX",
            "A3 NOOP",
            "A4 SELECT \"[Gmail]/Sent Mail\"",
            "A5 NOOP",
            "A6 NOOP",
            "A7 SELECT INBOX",
            "A8 NOOP",
        ])
        XCTAssertEqual(factory.count, 1)
    }

    /// IDLE watches INBOX: after a command browsed another folder, the
    /// idle re-selects INBOX before parking.
    func testIdleReselectsInboxAfterRunInAnotherMailbox() async throws {
        let transport = FakeMailTransport()
        await scriptOpen(transport, capabilities: "IMAP4rev1 IDLE")
        await transport.enqueueResponse(tag: "A3", untagged: ["* 8 EXISTS"], status: "OK SELECT completed")
        await transport.enqueueResponse(tag: "A4", status: "OK NOOP completed")
        await transport.enqueueResponse(tag: "A5", untagged: ["* 1 EXISTS"], status: "OK SELECT completed")
        await transport.enqueueLine("+ idling")
        await transport.enqueueHold()
        let factory = TransportFactory([transport])
        let session = makeSession(factory)

        try await session.run(in: "Spam") { try await $0.ping() }
        let idle = Task { try await session.idle { _ in } }
        await waitUntil { await transport.written.last == "A6 IDLE" }

        let written = await transport.written
        XCTAssertEqual(written, [
            "A1 LOGIN \"u\" \"p\"",
            "A2 SELECT INBOX",
            "A3 SELECT \"Spam\"",
            "A4 NOOP",
            "A5 SELECT INBOX",
            "A6 IDLE",
        ])

        let closing = Task { await session.close() }
        await waitUntil { await transport.written.last == "DONE" }
        await transport.enqueueLine("A6 OK IDLE terminated")
        await transport.enqueueResponse(tag: "A7", untagged: ["* BYE"], status: "OK LOGOUT completed")
        await closing.value
        try await idle.value
        XCTAssertEqual(factory.count, 1)
    }

    // MARK: - IDLE

    /// A command arriving mid-IDLE ends the idle first (DONE, tagged OK),
    /// runs, and the re-entered idle queues behind it.
    func testRunWhileIdlingStopsIdleFirstAndIdleResumesAfter() async throws {
        let transport = FakeMailTransport()
        await scriptOpen(transport, capabilities: "IMAP4rev1 IDLE")
        await transport.enqueueLine("+ idling")
        await transport.enqueueHold()
        let factory = TransportFactory([transport])
        let session = makeSession(factory)
        let recorder = Recorder()
        let open = "A1 LOGIN \"u\" \"p\""

        let firstIdle = Task {
            try await session.idle { event in
                Task { await recorder.add("event \(event)") }
            }
        }
        await waitUntil { await transport.written.last == "A3 IDLE" }

        let ping = Task {
            try await session.run { client in
                await recorder.add("ping")
                try await client.ping()
            }
        }
        await waitUntil { await transport.written.last == "DONE" }
        let midway = await transport.written
        XCTAssertEqual(midway, [open, "A2 SELECT INBOX", "A3 IDLE", "DONE"], "NOOP must wait for the idle to end")
        let bodyStarted = await recorder.events
        XCTAssertEqual(bodyStarted, [], "the body runs only after the tagged OK")

        await transport.enqueueLine("A3 OK IDLE terminated")
        await transport.enqueueResponse(tag: "A4", status: "OK NOOP completed")
        try await ping.value
        try await firstIdle.value

        // Re-entering: a fresh IDLE on the same connection.
        await transport.enqueueLine("+ idling")
        await transport.enqueueHold()
        let secondIdle = Task { try await session.idle { _ in } }
        await waitUntil { await transport.written.last == "A5 IDLE" }
        let written = await transport.written
        XCTAssertEqual(written, [open, "A2 SELECT INBOX", "A3 IDLE", "DONE", "A4 NOOP", "A5 IDLE"])
        XCTAssertEqual(factory.count, 1, "one connection throughout")

        // close() ends the idle the same way, then logs out.
        let closing = Task { await session.close() }
        await waitUntil { await transport.written.last == "DONE" }
        await transport.enqueueLine("A5 OK IDLE terminated")
        await transport.enqueueResponse(tag: "A6", untagged: ["* BYE"], status: "OK LOGOUT completed")
        await closing.value
        try await secondIdle.value
        let final = await transport.written
        XCTAssertEqual(final.suffix(3), ["A5 IDLE", "DONE", "A6 LOGOUT"])
    }

    /// Events reach the caller while idling; a `* BYE` ends the idle with
    /// `connectionClosed` and the next command reconnects.
    func testIdleDeliversEventsAndByeSurfacesAsConnectionClosed() async throws {
        let stale = FakeMailTransport()
        await scriptOpen(stale)
        // Capabilities were not in the greeting: the session asks.
        await stale.enqueueResponse(tag: "A3", untagged: ["* CAPABILITY IMAP4rev1 IDLE"], status: "OK done")
        await stale.enqueueLine("+ idling")
        await stale.enqueueLine("* 7 EXISTS")
        await stale.enqueueLine("* BYE Shutting down")
        let fresh = FakeMailTransport()
        await scriptOpen(fresh, exists: 7)
        await fresh.enqueueResponse(tag: "A3", status: "OK NOOP completed")
        let factory = TransportFactory([stale, fresh])
        let session = makeSession(factory)
        let recorder = Recorder()

        do {
            try await session.idle { event in
                Task { await recorder.add("event \(event)") }
            }
            XCTFail("expected connectionClosed")
        } catch MailError.connectionClosed {
            // expected
        }
        await waitUntil { await recorder.events == ["event exists 7"] }
        let events = await recorder.events
        XCTAssertEqual(events, ["event exists 7"])
        // The dead socket is logged out (best effort) and dropped.
        let staleWritten = await stale.written
        XCTAssertEqual(staleWritten.suffix(3), ["A3 CAPABILITY", "A4 IDLE", "A5 LOGOUT"])

        try await session.run { try await $0.ping() }
        XCTAssertEqual(factory.count, 2, "the dead connection is replaced")
    }

    func testIdleOnServerWithoutIdleThrowsUnsupported() async throws {
        let transport = FakeMailTransport()
        await scriptOpen(transport, capabilities: "IMAP4rev1 AUTH=PLAIN")
        let factory = TransportFactory([transport])
        let session = makeSession(factory)

        do {
            try await session.idle { _ in }
            XCTFail("expected idleUnsupported")
        } catch MailSessionError.idleUnsupported {
            // expected
        }
        let written = await transport.written
        XCTAssertEqual(written.count, 2, "no IDLE (and no CAPABILITY round trip: the greeting had it)")
    }

    /// Cancelling the calling task ends the idle cleanly — DONE, tagged OK —
    /// and returns rather than throwing.
    func testCancellingTheCallerStopsIdle() async throws {
        let transport = FakeMailTransport()
        await scriptOpen(transport, capabilities: "IMAP4rev1 IDLE")
        await transport.enqueueLine("+ idling")
        await transport.enqueueHold()
        let factory = TransportFactory([transport])
        let session = makeSession(factory)

        let idle = Task { try await session.idle { _ in } }
        await waitUntil { await transport.written.last == "A3 IDLE" }
        idle.cancel()
        await waitUntil { await transport.written.last == "DONE" }
        await transport.enqueueLine("A3 OK IDLE terminated")

        try await idle.value
        XCTAssertEqual(factory.count, 1)
    }
}
