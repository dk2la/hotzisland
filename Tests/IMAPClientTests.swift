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

    // MARK: - Mailboxes

    /// SPECIAL-USE attributes name the roles; names come quoted (with
    /// spaces) or as literals, and both must land intact.
    func testListSpecialUseParsesAttributesQuotedAndLiteralNames() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport, capabilities: "IMAP4rev1 SPECIAL-USE LIST-EXTENDED")
        await transport.enqueueLine("* LIST (\\HasNoChildren) \"/\" INBOX")
        await transport.enqueueLine("* LIST (\\HasNoChildren \\Junk) \"/\" \"Junk Mail\"")
        await transport.enqueueLine("* LIST (\\HasNoChildren \\Sent) \"/\" {13}")
        await transport.enqueueLiteral(Data("Sent Messages".utf8))
        await transport.enqueueLine("")
        await transport.enqueueLine("* LIST (\\Noselect \\HasChildren) \"/\" \"Folders\"")
        await transport.enqueueLine("* LIST (\\HasNoChildren \\Trash) \"/\" Trash")
        await transport.enqueueLine("* LIST (\\HasNoChildren \\Drafts) \"/\" Drafts")
        await transport.enqueueResponse(tag: "A1", status: "OK LIST completed")

        let folders = try await client.listSpecialUse()

        let written = await transport.written
        XCTAssertEqual(written, ["A1 LIST \"\" \"*\" RETURN (SPECIAL-USE)"])
        XCTAssertEqual(folders.junk, "Junk Mail")
        XCTAssertEqual(folders.sent, "Sent Messages")
        XCTAssertEqual(folders.trash, "Trash")
        XCTAssertEqual(folders.drafts, "Drafts")
        XCTAssertNil(folders.flagged)
        XCTAssertNil(folders.important)
        XCTAssertNil(folders.all)
        let isGmail = await client.isGmail
        XCTAssertFalse(isGmail)
    }

    /// Gmail without SPECIAL-USE: XLIST, with its own attribute names.
    func testListOnGmailUsesXlistAndItsAttributeNames() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport, capabilities: "IMAP4rev1 IDLE X-GM-EXT-1")
        await transport.enqueueLine("* XLIST (\\HasNoChildren \\Inbox) \"/\" \"Inbox\"")
        await transport.enqueueLine("* XLIST (\\Noselect \\HasChildren) \"/\" \"[Gmail]\"")
        await transport.enqueueLine("* XLIST (\\HasNoChildren \\AllMail) \"/\" \"[Gmail]/All Mail\"")
        await transport.enqueueLine("* XLIST (\\HasNoChildren \\Important) \"/\" \"[Gmail]/Important\"")
        await transport.enqueueLine("* XLIST (\\HasNoChildren \\Sent) \"/\" \"[Gmail]/Sent Mail\"")
        await transport.enqueueLine("* XLIST (\\HasNoChildren \\Spam) \"/\" \"[Gmail]/Spam\"")
        await transport.enqueueLine("* XLIST (\\HasNoChildren \\Starred) \"/\" \"[Gmail]/Starred\"")
        await transport.enqueueLine("* XLIST (\\HasNoChildren \\Trash) \"/\" \"[Gmail]/Trash\"")
        await transport.enqueueResponse(tag: "A1", status: "OK Success")

        let folders = try await client.listSpecialUse()

        let written = await transport.written
        XCTAssertEqual(written, ["A1 XLIST \"\" \"*\""])
        XCTAssertEqual(folders.junk, "[Gmail]/Spam")
        XCTAssertEqual(folders.sent, "[Gmail]/Sent Mail")
        XCTAssertEqual(folders.flagged, "[Gmail]/Starred")
        XCTAssertEqual(folders.important, "[Gmail]/Important")
        XCTAssertEqual(folders.all, "[Gmail]/All Mail")
        XCTAssertEqual(folders.trash, "[Gmail]/Trash")
        let isGmail = await client.isGmail
        XCTAssertTrue(isGmail)
    }

    /// No attributes at all: the usual folder names stand in for them.
    func testListWithoutAttributesFallsBackToCommonNames() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport)
        await transport.enqueueLine("* LIST () \".\" INBOX")
        await transport.enqueueLine("* LIST (\\HasNoChildren) \".\" \"Spam\"")
        await transport.enqueueLine("* LIST (\\HasNoChildren) \".\" \"Sent\"")
        await transport.enqueueLine("* LIST (\\HasNoChildren) \".\" \"Archive\"")
        await transport.enqueueResponse(tag: "A1", status: "OK LIST completed")

        let folders = try await client.listSpecialUse()

        let written = await transport.written
        XCTAssertEqual(written, ["A1 LIST \"\" \"*\""])
        XCTAssertEqual(folders.junk, "Spam")
        XCTAssertEqual(folders.sent, "Sent")
        XCTAssertNil(folders.important)
    }

    func testSelectSendsQuotedFolderAndTracksSelectedMailbox() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport)
        let before = await client.selectedMailbox
        XCTAssertNil(before)
        await transport.enqueueResponse(tag: "A1", untagged: ["* 7 EXISTS"], status: "OK [READ-WRITE] SELECT completed")
        await transport.enqueueResponse(tag: "A2", untagged: ["* 42 EXISTS"], status: "OK [READ-WRITE] SELECT completed")

        let sentExists = try await client.select("[Gmail]/Sent Mail")
        let afterSent = await client.selectedMailbox
        XCTAssertEqual(sentExists, 7)
        XCTAssertEqual(afterSent, "[Gmail]/Sent Mail")

        let inboxExists = try await client.selectInbox()
        let afterInbox = await client.selectedMailbox
        XCTAssertEqual(inboxExists, 42)
        XCTAssertEqual(afterInbox, "INBOX")

        let written = await transport.written
        XCTAssertEqual(written, ["A1 SELECT \"[Gmail]/Sent Mail\"", "A2 SELECT INBOX"])
    }

    /// A refused SELECT leaves no mailbox selected.
    func testRefusedSelectClearsSelectedMailbox() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport)
        await transport.enqueueResponse(tag: "A1", untagged: ["* 1 EXISTS"], status: "OK SELECT completed")
        await transport.enqueueResponse(tag: "A2", status: "NO [NONEXISTENT] Unknown Mailbox")

        _ = try await client.selectInbox()
        do {
            _ = try await client.select("Nope")
            XCTFail("expected badResponse")
        } catch MailError.badResponse {
            // expected
        }
        let selected = await client.selectedMailbox
        XCTAssertNil(selected)
    }

    /// The UIDs a search returns are what the header fetch asks for —
    /// newest first, capped — and the messages carry the selected folder.
    func testSearchResultFeedsTheHeaderFetchOfThoseUIDs() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport)
        await transport.enqueueResponse(tag: "A1", untagged: ["* 50 EXISTS"], status: "OK SELECT completed")
        await transport.enqueueResponse(tag: "A2", untagged: ["* SEARCH 3 41 17"], status: "OK SEARCH completed")
        let envelope = "(\"Mon, 25 Aug 2026 12:05:00 +0300\" \"Hi\" ((\"Anna\" NIL \"anna\" \"acme.io\")) "
            + "((\"Anna\" NIL \"anna\" \"acme.io\")) ((\"Anna\" NIL \"anna\" \"acme.io\")) "
            + "((NIL NIL \"d\" \"gmail.com\")) NIL NIL NIL \"<x@acme.io>\")"
        await transport.enqueueResponse(
            tag: "A3",
            untagged: [
                "* 12 FETCH (UID 17 FLAGS (\\Flagged) ENVELOPE \(envelope))",
                "* 30 FETCH (UID 41 FLAGS (\\Flagged \\Seen) ENVELOPE \(envelope))",
            ],
            status: "OK FETCH completed"
        )

        _ = try await client.selectInbox()
        let messages = try await client.fetchHeaders(searching: "FLAGGED", limit: 2)

        let written = await transport.written
        XCTAssertEqual(written, [
            "A1 SELECT INBOX",
            "A2 UID SEARCH FLAGGED",
            "A3 UID FETCH 41,17 (UID FLAGS INTERNALDATE ENVELOPE BODYSTRUCTURE)",
        ])
        XCTAssertEqual(messages.map(\.uid), [17, 41], "same date: order as fetched")
        XCTAssertEqual(messages.map(\.mailbox), ["INBOX", "INBOX"])
        XCTAssertEqual(messages.map(\.isUnread), [true, false])
    }

    func testHeadersCarryTheSelectedFolder() async throws {
        let transport = FakeMailTransport()
        let client = try await connectedClient(transport)
        await transport.enqueueResponse(tag: "A1", untagged: ["* 2 EXISTS"], status: "OK SELECT completed")
        await transport.enqueueResponse(
            tag: "A2",
            untagged: ["* 2 FETCH (UID 9 FLAGS (\\Seen) ENVELOPE (\"Mon, 25 Aug 2026 12:05:00 +0300\" \"Out\" "
                + "((\"Me\" NIL \"d\" \"gmail.com\")) ((\"Me\" NIL \"d\" \"gmail.com\")) ((\"Me\" NIL \"d\" \"gmail.com\")) "
                + "((\"Boris Ivanov\" NIL \"boris\" \"acme.io\")) NIL NIL NIL \"<o@gmail.com>\"))"],
            status: "OK FETCH completed"
        )

        let exists = try await client.select("[Gmail]/Sent Mail")
        let messages = try await client.fetchHeaders(exists: exists, limit: 30)

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.mailbox, "[Gmail]/Sent Mail")
        XCTAssertEqual(messages.first?.key, MessageKey(mailbox: "[Gmail]/Sent Mail", uid: 9))
        XCTAssertEqual(messages.first?.toName, "Boris Ivanov")
        XCTAssertEqual(messages.first?.recipientDisplay, "Boris Ivanov")
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
