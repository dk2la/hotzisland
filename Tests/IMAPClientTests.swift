import XCTest

/// Wire-level behaviour of `IMAPClient` against a scripted transport: the
/// commands it writes, tag matching, literal inlining and dropped sockets.
final class IMAPClientTests: XCTestCase {
    private func connectedClient(
        _ transport: FakeMailTransport,
        capabilities: String? = nil
    ) async throws -> IMAPClient {
        await transport.enqueueGreeting(capabilities: capabilities)
        let client = IMAPClient(transport: transport)
        try await client.connect()
        return client
    }

    private actor EventRecorder {
        private(set) var events: [IMAPClient.IdleEvent] = []
        func add(_ event: IMAPClient.IdleEvent) { events.append(event) }
    }

    private func waitUntil(_ condition: @escaping @Sendable () async -> Bool) async {
        for _ in 0..<400 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func testLoginAndSelectSendExpectedCommandsAndParseExists() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport)
        await transport.enqueueResponse(tag: "A1", status: "OK LOGIN completed")
        await transport.enqueueResponse(
            tag: "A2",
            untagged: ["* FLAGS (\\Seen \\Answered)", "* 42 EXISTS", "* 0 RECENT", "* OK [UIDVALIDITY 1]"],
            status: "OK [READ-WRITE] SELECT completed"
        )

        try await client.login(user: "d@example.com", password: "p\"w\\d")
        let exists = try await client.selectInbox()

        XCTAssertEqual(exists, 42)
        // Quotes and backslashes in the password must be escaped on the wire.
        let written = await transport.written
        XCTAssertEqual(written, [
            "A1 LOGIN \"d@example.com\" \"p\\\"w\\\\d\"",
            "A2 SELECT INBOX",
        ])
        let connects = await transport.connectCount
        XCTAssertEqual(connects, 1)
    }

    /// "{n}" at the end of a line is followed by n raw bytes and then the
    /// rest of the response unit — the client must splice all of it into
    /// one unit before the parser sees it.
    func testLiteralInFetchReplyIsInlinedIntoTheUnit() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport)
        let subject = "=?UTF-8?B?0J/RgNC40LLQtdGCLCDQvNC40YA=?="
        await transport.enqueueLine(
            "* 3 FETCH (UID 77 FLAGS () INTERNALDATE \"25-Aug-2026 09:05:00 +0000\" "
                + "ENVELOPE (\"Mon, 25 Aug 2026 12:05:00 +0300\" {\(subject.utf8.count)}"
        )
        await transport.enqueueLiteral(Data(subject.utf8))
        await transport.enqueueLine(
            " ((\"Yandex\" NIL \"noreply\" \"yandex.ru\")) ((\"Yandex\" NIL \"noreply\" \"yandex.ru\")) "
                + "((\"Yandex\" NIL \"noreply\" \"yandex.ru\")) ((NIL NIL \"d\" \"gmail.com\")) "
                + "NIL NIL NIL \"<xyz@yandex.ru>\") "
                + "BODYSTRUCTURE (\"TEXT\" \"PLAIN\" (\"CHARSET\" \"UTF-8\") NIL NIL \"8BIT\" 400 10 NIL NIL NIL NIL))"
        )
        await transport.enqueueResponse(tag: "A1", status: "OK FETCH completed")

        let messages = try await client.fetchHeaders(uids: [77])

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.uid, 77)
        XCTAssertEqual(messages.first?.subject, "Привет, мир")
        XCTAssertEqual(messages.first?.textPart?.section, "1")
        let literalReads = await transport.literalReads
        XCTAssertEqual(literalReads, [subject.utf8.count], "exactly one literal of the announced size")
        let written = await transport.written
        XCTAssertEqual(written, ["A1 UID FETCH 77 (UID FLAGS INTERNALDATE ENVELOPE BODYSTRUCTURE)"])
    }

    /// A tagged line for another tag (or one that merely shares a prefix,
    /// "A10" vs "A1") is response data, not our completion.
    func testReplyForAnotherTagIsNotMistakenForOurs() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport)
        await transport.enqueueResponse(
            tag: "A1",
            untagged: ["A10 NO not yours", "A7 BAD nor this"],
            status: "OK LOGIN completed"
        )
        await transport.enqueueResponse(
            tag: "A2",
            untagged: ["A20 NO still not yours", "* 5 EXISTS"],
            status: "OK SELECT completed"
        )

        try await client.login(user: "u", password: "p")
        let exists = try await client.selectInbox()
        XCTAssertEqual(exists, 5)
    }

    func testNoReplyIsAuthFailureOnLogin() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport)
        await transport.enqueueResponse(tag: "A1", status: "NO [AUTHENTICATIONFAILED] Invalid credentials")

        do {
            try await client.login(user: "u", password: "p")
            XCTFail("expected authFailed")
        } catch let MailError.authFailed(message) {
            XCTAssertEqual(message, "NO [AUTHENTICATIONFAILED] Invalid credentials")
        }
    }

    /// The transport runs out of scripted lines mid-command: the socket is
    /// gone, and that must surface as `connectionClosed`.
    func testDroppedConnectionSurfacesAsConnectionClosed() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport)

        do {
            try await client.login(user: "u", password: "p")
            XCTFail("expected connectionClosed")
        } catch MailError.connectionClosed {
            // expected
        }
    }

    /// The client does not recognise "* BYE" itself; the server closes the
    /// socket right after it, and that close is what the caller sees.
    func testByeFollowedByCloseSurfacesAsConnectionClosed() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport)
        await transport.enqueueLine("* BYE Autologout; idle for too long")

        do {
            _ = try await client.selectInbox()
            XCTFail("expected connectionClosed")
        } catch MailError.connectionClosed {
            // expected
        }
    }

    func testLogoutSendsCommandAndClosesTransport() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport)
        await transport.enqueueResponse(tag: "A1", untagged: ["* BYE"], status: "OK LOGOUT completed")

        await client.logout()

        let written = await transport.written
        XCTAssertEqual(written, ["A1 LOGOUT"])
        let closes = await transport.closeCount
        XCTAssertEqual(closes, 1)
    }

    // MARK: - CAPABILITY

    func testCapabilityComesFromTheGreetingCode() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport, capabilities: "IMAP4rev1 IDLE NAMESPACE")

        let supportsIdle = await client.supportsIdle
        XCTAssertTrue(supportsIdle)
        let capabilities = await client.capabilities
        XCTAssertEqual(capabilities, ["IMAP4REV1", "IDLE", "NAMESPACE"])
    }

    func testCapabilityCommandFillsInWhenTheGreetingHasNone() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport)
        let unknown = await client.capabilities
        XCTAssertNil(unknown, "nothing advertised yet")
        await transport.enqueueResponse(
            tag: "A1",
            untagged: ["* CAPABILITY IMAP4rev1 UNSELECT IDLE X-GM-EXT-1"],
            status: "OK Thats all she wrote!"
        )

        try await client.fetchCapabilities()

        let supportsIdle = await client.supportsIdle
        XCTAssertTrue(supportsIdle)
        let written = await transport.written
        XCTAssertEqual(written, ["A1 CAPABILITY"])
    }

    /// Dovecot answers LOGIN with the post-auth list in the tagged OK.
    func testCapabilityCodeOnTaggedLoginReplyIsPickedUp() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport, capabilities: "IMAP4rev1 AUTH=PLAIN")
        let before = await client.supportsIdle
        XCTAssertFalse(before)
        await transport.enqueueResponse(tag: "A1", status: "OK [CAPABILITY IMAP4rev1 IDLE MOVE] Logged in")

        try await client.login(user: "u", password: "p")

        let after = await client.supportsIdle
        XCTAssertTrue(after)
    }

    func testServerWithoutIdleIsReportedAsSuch() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport)
        await transport.enqueueResponse(tag: "A1", untagged: ["* CAPABILITY IMAP4rev1 AUTH=PLAIN"])

        try await client.fetchCapabilities()

        let supportsIdle = await client.supportsIdle
        XCTAssertFalse(supportsIdle)
    }

    // MARK: - IDLE

    /// IDLE, `+`, updates reported as they arrive, DONE, tagged OK.
    func testIdleReportsExistsAndEndsWithDone() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport)
        await transport.enqueueLine("+ idling")
        await transport.enqueueLine("* 5 EXISTS")
        await transport.enqueueLine("* 1 RECENT")
        await transport.enqueueLine("* 3 EXPUNGE")
        await transport.enqueueLine("* 2 FETCH (FLAGS (\\Seen))")
        await transport.enqueueHold()
        let events = EventRecorder()

        let idle = Task {
            try await client.idle { event in
                Task { await events.add(event) }
            }
        }
        await waitUntil { await events.events.count == 3 }
        let seen = await events.events
        XCTAssertEqual(seen, [.exists(5), .expunge(3), .flags(2)], "RECENT is not a change worth a refresh")
        let stillIdling = await client.isIdling
        XCTAssertTrue(stillIdling)

        // DONE goes out first; only then does the server end the command.
        try await client.stopIdle()
        let written = await transport.written
        XCTAssertEqual(written, ["A1 IDLE", "DONE"])
        await transport.enqueueLine("A1 OK IDLE terminated")
        try await idle.value

        let idling = await client.isIdling
        XCTAssertFalse(idling)
        // Second DONE has nothing to end.
        try await client.stopIdle()
        let after = await transport.written
        XCTAssertEqual(after, ["A1 IDLE", "DONE"])
    }

    func testUpdatesAheadOfTheContinuationAreNotLost() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport)
        await transport.enqueueLine("* 9 EXISTS")
        await transport.enqueueLine("+ idling")
        await transport.enqueueLine("A1 OK IDLE terminated")
        let events = EventRecorder()

        try await client.idle { event in
            Task { await events.add(event) }
        }

        await waitUntil { await events.events == [.exists(9)] }
        let seen = await events.events
        XCTAssertEqual(seen, [.exists(9)])
    }

    func testByeDuringIdleSurfacesAsConnectionClosed() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport)
        await transport.enqueueLine("+ idling")
        await transport.enqueueLine("* BYE Autologout; idle for too long")

        do {
            try await client.idle { _ in }
            XCTFail("expected connectionClosed")
        } catch MailError.connectionClosed {
            // expected
        }
        let idling = await client.isIdling
        XCTAssertFalse(idling)
    }

    func testIdleRefusedByServerIsBadResponse() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport)
        await transport.enqueueResponse(tag: "A1", status: "BAD Unknown command")

        do {
            try await client.idle { _ in }
            XCTFail("expected badResponse")
        } catch let MailError.badResponse(message) {
            XCTAssertEqual(message, "BAD Unknown command")
        }
    }

    /// The IDLE read blocks; `logout` must not queue a LOGOUT behind it and
    /// wait for a reply the idle loop would eat — it just drops the socket.
    func testLogoutWhileIdlingDropsTheSocketWithoutLogoutCommand() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport)
        await transport.enqueueLine("+ idling")
        await transport.enqueueHold()
        let idle = Task { try await client.idle { _ in } }
        await waitUntil { await transport.written == ["A1 IDLE"] }

        await client.logout()

        do {
            try await idle.value
            XCTFail("expected connectionClosed")
        } catch MailError.connectionClosed {
            // expected
        }
        let written = await transport.written
        XCTAssertEqual(written, ["A1 IDLE"])
        let closes = await transport.closeCount
        XCTAssertEqual(closes, 1)
    }
}
