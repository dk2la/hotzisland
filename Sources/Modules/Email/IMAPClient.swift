import Foundation
import OSLog

/// Minimal IMAP4rev1 client scoped to one INBOX session: login, unseen
/// search, header fetch, body fetch, mark seen. Connection lifetime is
/// `MailSession`'s job — this type owns the wire protocol only.
actor IMAPClient {
    private let transport: any MailLineTransport
    private var tagCounter = 0
    private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "email")
    /// Cap for the structure-free body fetch (256 KB).
    private static let bodyByteLimit = 262_144
    /// What the server advertised: the greeting's `[CAPABILITY …]` code, an
    /// untagged `* CAPABILITY` (Gmail pushes one right after LOGIN, Dovecot
    /// puts it in the tagged OK) or the reply to an explicit CAPABILITY.
    /// nil until the server has said anything at all.
    private(set) var capabilities: Set<String>?

    init(host: String, port: UInt16) {
        self.init(transport: TLSTransport(host: host, port: port))
    }

    /// Wire the protocol onto any transport — tests pass a scripted one.
    init(transport: any MailLineTransport) {
        self.transport = transport
    }

    // MARK: - Session

    func connect() async throws {
        try await transport.connect()
        // Server greeting: "* OK ..."
        let greeting = try await transport.readLine(timeout: .seconds(15))
        let text = String(decoding: greeting, as: UTF8.self)
        guard text.uppercased().contains("OK") else {
            throw MailError.badResponse(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        noteCapabilities(in: greeting)
    }

    var supportsIdle: Bool { capabilities?.contains("IDLE") ?? false }

    /// Asks explicitly — for servers whose greeting and LOGIN reply carry no
    /// capability list.
    func fetchCapabilities() async throws {
        _ = try await command("CAPABILITY")
    }

    func login(user: String, password: String) async throws {
        do {
            _ = try await command("LOGIN \(quote(user)) \(quote(password))")
        } catch let MailError.badResponse(message) {
            throw MailError.authFailed(message)
        }
    }

    /// Selects INBOX; returns the EXISTS count.
    func selectInbox() async throws -> Int {
        let units = try await command("SELECT INBOX")
        for unit in units {
            if let exists = IMAPParser.parseExists(unit) {
                return exists
            }
        }
        return 0
    }

    /// Unread count. STATUS answers with a single number; UID SEARCH would
    /// stream back every unread UID — on a neglected inbox that is a
    /// six-figure line of digits every poll.
    func searchUnseenCount() async throws -> Int {
        if let units = try? await command("STATUS INBOX (UNSEEN)") {
            for unit in units {
                if let count = IMAPParser.parseStatusUnseen(unit) {
                    return count
                }
            }
        }
        let units = try await command("UID SEARCH UNSEEN")
        for unit in units {
            if let uids = IMAPParser.parseSearch(unit) {
                return uids.count
            }
        }
        return 0
    }

    /// Fetches ENVELOPE + FLAGS + BODYSTRUCTURE for the newest `limit`
    /// messages of a mailbox with `exists` messages.
    func fetchHeaders(exists: Int, limit: Int) async throws -> [EmailMessage] {
        guard exists > 0 else { return [] }
        let from = max(1, exists - limit + 1)
        let units = try await command(
            "FETCH \(from):* (UID FLAGS INTERNALDATE ENVELOPE BODYSTRUCTURE)"
        )
        return Self.buildMessages(from: units, log: log)
    }

    /// Same header fetch, addressed by UID — search results come as UIDs.
    func fetchHeaders(uids: [UInt32]) async throws -> [EmailMessage] {
        guard !uids.isEmpty else { return [] }
        let set = uids.map(String.init).joined(separator: ",")
        let units = try await command(
            "UID FETCH \(set) (UID FLAGS INTERNALDATE ENVELOPE BODYSTRUCTURE)"
        )
        return Self.buildMessages(from: units, log: log)
    }

    private static func buildMessages(from units: [Data], log: Logger) -> [EmailMessage] {
        var messages: [EmailMessage] = []
        for unit in units {
            guard let item = IMAPParser.parseFetch(unit), let uid = item.uid else { continue }
            let envelope = item.envelope
            messages.append(EmailMessage(
                uid: uid,
                subject: envelope?.subject ?? "",
                fromName: envelope?.fromName ?? "",
                fromAddress: envelope?.fromAddress ?? "",
                replyTo: envelope?.replyTo,
                to: envelope?.to ?? [],
                cc: envelope?.cc ?? [],
                date: envelope?.date ?? item.internalDate ?? .distantPast,
                isUnread: !item.flags.contains { $0.caseInsensitiveCompare("\\Seen") == .orderedSame },
                messageID: envelope?.messageID,
                references: [envelope?.inReplyTo].compactMap { $0 },
                bodyPlain: nil,
                textPart: item.textPart
            ))
        }
        messages.sort { $0.date > $1.date }
        // Counts only — a drop in either column means the parser lost ground.
        let named = messages.filter { !$0.subject.isEmpty }.count
        let structured = messages.filter { $0.textPart != nil }.count
        log.info("headers n=\(messages.count, privacy: .public) subjects=\(named, privacy: .public) parts=\(structured, privacy: .public)")
        return messages
    }

    /// Server-side full-text search over INBOX; newest `limit` UIDs. The
    /// local list only ever holds 30 headers, so "find yesterday's mail"
    /// has to ask the server.
    func searchUIDs(query: String, limit: Int) async throws -> [UInt32] {
        let bytes = Data(query.utf8)
        let isPlainASCII = bytes.allSatisfy { $0 >= 32 && $0 < 127 }
        let units: [Data]
        if isPlainASCII {
            units = try await command("UID SEARCH CHARSET UTF-8 TEXT \(quote(query))")
        } else {
            // Non-ASCII (Cyrillic…) cannot ride in a quoted string — RFC
            // requires a literal. The non-synchronizing `{n+}` form goes out
            // in one write; Gmail/Yandex/iCloud all speak LITERAL+.
            units = try await command(
                "UID SEARCH CHARSET UTF-8 TEXT ",
                literal: bytes
            )
        }
        for unit in units {
            if let uids = IMAPParser.parseSearch(unit) {
                return Array(uids.sorted(by: >).prefix(limit))
            }
        }
        return []
    }

    /// RFC 6851 UID MOVE — archive is "move out of INBOX" everywhere; on
    /// Gmail the destination is All Mail (labels, not folders).
    func move(uid: UInt32, to mailbox: String) async throws {
        _ = try await command("UID MOVE \(uid) \(quote(mailbox))")
    }

    /// Fetches and decodes the readable text of one message: the part that
    /// BODYSTRUCTURE pointed at, or — when it pointed at nothing — the raw
    /// body plus its content headers, walked locally. The References header
    /// rides along; replies need it and ENVELOPE does not carry it.
    func fetchBody(uid: UInt32, part: EmailMessage.TextPartInfo?) async throws -> MessageBody {
        if let part {
            let units = try await command(
                "UID FETCH \(uid) (BODY.PEEK[\(part.section)] BODY.PEEK[HEADER.FIELDS (REFERENCES)])"
            )
            for unit in units {
                guard let item = IMAPParser.parseFetch(unit),
                      let payload = item.bodyPayloads[part.section.uppercased()]
                else { continue }
                let decoded = MIMEDecode.decodeBody(payload, encoding: part.encoding, charset: part.charset)
                // Senders routinely mislabel HTML as text/plain — detect by
                // content, not just by the declared subtype.
                let isHTML = part.isHTML || MIMEDecode.looksLikeHTML(decoded)
                let text = isHTML ? MIMEDecode.htmlToPlainText(decoded) : decoded
                log.info("body uid=\(uid, privacy: .public) section=\(part.section, privacy: .public) enc=\(part.encoding, privacy: .public) chars=\(text.count, privacy: .public) html=\(isHTML, privacy: .public)")
                return MessageBody(
                    text: text,
                    references: Self.references(in: item),
                    html: isHTML ? decoded : nil
                )
            }
        }
        return try await fetchWholeBody(uid: uid)
    }

    /// Structure-free fallback. Capped with a partial fetch so a message
    /// carrying a fat attachment cannot stall the panel.
    private func fetchWholeBody(uid: UInt32) async throws -> MessageBody {
        let headerFields = "BODY.PEEK[HEADER.FIELDS (CONTENT-TYPE CONTENT-TRANSFER-ENCODING REFERENCES)]"
        let units = try await command(
            "UID FETCH \(uid) (\(headerFields) BODY.PEEK[TEXT]<0.\(Self.bodyByteLimit)>)"
        )
        for unit in units {
            guard let item = IMAPParser.parseFetch(unit), let body = item.bodyPayloads["TEXT"] else { continue }
            let rawHeaders = item.bodyPayloads.first { $0.key.hasPrefix("HEADER.FIELDS") }?.value ?? Data()
            let headers = MIMEDecode.parseHeaders(rawHeaders)
            let readable = MIMEDecode.extractReadable(
                rawBody: body,
                contentType: headers["content-type"] ?? "text/plain",
                transferEncoding: headers["content-transfer-encoding"] ?? "7bit"
            )
            log.info("body fallback uid=\(uid, privacy: .public) bytes=\(body.count, privacy: .public) chars=\(readable.text.count, privacy: .public)")
            return MessageBody(text: readable.text, references: Self.references(in: item), html: readable.html)
        }
        return MessageBody(text: "", references: [])
    }

    /// "<a@x> <b@y>" from whichever HEADER.FIELDS payload came back.
    private static func references(in item: IMAPParser.FetchItem) -> [String] {
        guard let raw = item.bodyPayloads.first(where: { $0.key.hasPrefix("HEADER.FIELDS") })?.value,
              let value = MIMEDecode.parseHeaders(raw)["references"]
        else { return [] }
        return value.split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.hasPrefix("<") && $0.hasSuffix(">") }
    }

    /// Cheap liveness probe. A silently dropped socket only reveals itself
    /// on the next read, so a reused session is validated with a short-timeout
    /// NOOP rather than by stalling a real command for the full 15 seconds.
    func ping() async throws {
        _ = try await command("NOOP", timeout: .seconds(3))
    }

    func markSeen(uid: UInt32) async throws {
        _ = try await command("UID STORE \(uid) +FLAGS.SILENT (\\Seen)")
    }

    func logout() async {
        // A pending idle read owns the socket and would swallow LOGOUT's
        // reply; a session that is still idling is simply dropped.
        if idleTag == nil {
            _ = try? await command("LOGOUT")
        }
        await transport.close()
    }

    /// Closes the socket without LOGOUT. Used to unblock an idle read that
    /// DONE could not end (dead server) and to discard a dead connection.
    func dropConnection() async {
        await transport.close()
    }

    // MARK: - IDLE (RFC 2177)

    /// A mailbox change pushed by the server while idling.
    enum IdleEvent: Sendable, Equatable, CustomStringConvertible {
        /// `* n EXISTS` — message count is now n (new mail, usually).
        case exists(Int)
        /// `* n EXPUNGE` — message n is gone.
        case expunge(Int)
        /// `* n FETCH (FLAGS …)` — message n's flags changed (read elsewhere).
        case flags(Int)

        var description: String {
            switch self {
            case .exists(let n): "exists \(n)"
            case .expunge(let n): "expunge \(n)"
            case .flags(let n): "flags \(n)"
            }
        }
    }

    /// Tag of the IDLE command in flight; nil when not idling.
    private var idleTag: String?
    private var idleDoneSent = false
    /// Untagged updates the server pushed ahead of its `+` continuation.
    private var pendingIdleEvents: [IdleEvent] = []
    /// One slice of the open-ended idle wait. A timeout is not an error
    /// here — the loop just checks for cancellation and reads again — so
    /// this is only how often a cancelled idle notices.
    private static let idleReadTimeout: Duration = .seconds(60)

    var isIdling: Bool { idleTag != nil }

    /// IDLE start to finish: sends the command, then reports mailbox changes
    /// through `onEvent` until `stopIdle()` ends it (returns) or the server
    /// goes away (throws). The actor is reentrant at the read, which is
    /// exactly how `stopIdle` gets in while this is blocked.
    func idle(onEvent: @escaping @Sendable (IdleEvent) -> Void) async throws {
        try await beginIdle()
        try await awaitIdle(onEvent: onEvent)
    }

    /// Sends IDLE and waits for the server's `+` continuation. Split from
    /// `awaitIdle` so a caller can serialize the start against other commands
    /// and then leave the open-ended wait to a side task.
    func beginIdle() async throws {
        guard idleTag == nil else { throw MailError.badResponse("IDLE already running") }
        tagCounter += 1
        let tag = "A\(tagCounter)"
        idleTag = tag
        idleDoneSent = false
        pendingIdleEvents = []
        do {
            try await transport.send(Data("\(tag) IDLE\r\n".utf8))
            while true {
                let unit = try await readUnit()
                let line = String(decoding: unit.prefix(200), as: UTF8.self)
                if line.hasPrefix("+") {
                    return
                }
                if line.hasPrefix("\(tag) ") {
                    // OK without a continuation is as wrong as NO/BAD.
                    throw MailError.badResponse(Self.taggedMessage(line, tag: tag))
                }
                if Self.isBye(line) {
                    throw MailError.connectionClosed
                }
                if let event = Self.idleEvent(in: line) {
                    pendingIdleEvents.append(event)
                }
            }
        } catch {
            idleTag = nil
            throw error
        }
    }

    /// The wait half of IDLE: reads until the tagged completion that DONE
    /// provokes. `* BYE` is the server hanging up.
    func awaitIdle(onEvent: @escaping @Sendable (IdleEvent) -> Void) async throws {
        guard let tag = idleTag else { return }
        defer { idleTag = nil }
        for event in pendingIdleEvents {
            onEvent(event)
        }
        pendingIdleEvents = []
        while true {
            let unit: Data
            do {
                unit = try await readUnit(timeout: Self.idleReadTimeout)
            } catch MailError.timeout {
                try Task.checkCancellation()
                continue
            }
            let line = String(decoding: unit.prefix(200), as: UTF8.self)
            if line.hasPrefix("\(tag) ") {
                if line.uppercased().hasPrefix("\(tag) OK") {
                    return
                }
                throw MailError.badResponse(Self.taggedMessage(line, tag: tag))
            }
            if Self.isBye(line) {
                throw MailError.connectionClosed
            }
            if let event = Self.idleEvent(in: line) {
                onEvent(event)
            }
        }
    }

    /// Writes DONE; the running `awaitIdle` then returns on the tagged OK.
    /// Idempotent — a second call while the first is pending is a no-op.
    func stopIdle() async throws {
        guard idleTag != nil, !idleDoneSent else { return }
        idleDoneSent = true
        try await transport.send(Data("DONE\r\n".utf8))
    }

    private static func isBye(_ line: String) -> Bool {
        line.uppercased().hasPrefix("* BYE")
    }

    private static func taggedMessage(_ line: String, tag: String) -> String {
        line.dropFirst(tag.count + 1).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "* 5 EXISTS", "* 3 EXPUNGE", "* 2 FETCH (FLAGS (\\Seen))" → event.
    private static func idleEvent(in line: String) -> IdleEvent? {
        let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count >= 3, parts[0] == "*", let number = Int(parts[1]) else { return nil }
        switch parts[2].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "EXISTS": return .exists(number)
        case "EXPUNGE": return .expunge(number)
        case "FETCH": return line.uppercased().contains("FLAGS") ? .flags(number) : nil
        default: return nil
        }
    }

    // MARK: - Wire protocol

    /// Sends one tagged command and gathers complete response units (each a
    /// line with any `{n}` literals inlined) until the tagged completion.
    private func command(_ text: String, timeout: Duration = .seconds(15)) async throws -> [Data] {
        tagCounter += 1
        let tag = "A\(tagCounter)"
        try await transport.send(Data("\(tag) \(text)\r\n".utf8))
        return try await readResponse(tag: tag, timeout: timeout)
    }

    /// Command whose last argument is a non-synchronizing literal (LITERAL+,
    /// RFC 7888): `{n+}` needs no continuation round trip, so the whole
    /// command goes out in one write.
    private func command(
        _ prefix: String,
        literal: Data,
        timeout: Duration = .seconds(15)
    ) async throws -> [Data] {
        tagCounter += 1
        let tag = "A\(tagCounter)"
        var payload = Data("\(tag) \(prefix){\(literal.count)+}\r\n".utf8)
        payload.append(literal)
        payload.append(Data("\r\n".utf8))
        try await transport.send(payload)
        return try await readResponse(tag: tag, timeout: timeout)
    }

    private func readResponse(tag: String, timeout: Duration) async throws -> [Data] {
        var units: [Data] = []
        while true {
            let unit = try await readUnit(timeout: timeout)
            let line = String(decoding: unit.prefix(200), as: UTF8.self)
            noteCapabilities(in: unit)
            if line.hasPrefix("\(tag) ") {
                let upper = line.uppercased()
                if upper.hasPrefix("\(tag) OK") {
                    return units
                }
                let message = line
                    .dropFirst(tag.count + 1)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw MailError.badResponse(message)
            }
            units.append(unit)
        }
    }

    /// Reads one full response unit: a CRLF line plus any literal payloads
    /// (lines ending in "{n}" are continued by n raw bytes and more line
    /// data, repeatedly).
    private func readUnit(timeout: Duration = .seconds(15)) async throws -> Data {
        var unit = Data()
        while true {
            let line = try await transport.readLine(timeout: timeout)
            unit.append(line)
            guard let size = trailingLiteralSize(of: line) else {
                return unit
            }
            let payload = try await transport.read(exactly: size)
            unit.append(payload)
        }
    }

    /// Picks a capability list out of `* CAPABILITY …` or a `[CAPABILITY …]`
    /// response code, wherever it appears. The 200-byte peek only decides
    /// whether to look; the list itself can run longer than that.
    private func noteCapabilities(in unit: Data) {
        let head = String(decoding: unit.prefix(200), as: UTF8.self).uppercased()
        guard head.hasPrefix("* CAPABILITY ") || head.contains("[CAPABILITY ") else { return }
        let end = unit.firstIndex(of: 13) ?? unit.endIndex
        let line = String(decoding: unit[unit.startIndex..<end], as: UTF8.self).uppercased()
        let list: Substring
        if line.hasPrefix("* CAPABILITY ") {
            list = line.dropFirst("* CAPABILITY ".count)
        } else if let open = line.range(of: "[CAPABILITY "),
                  let close = line[open.upperBound...].firstIndex(of: "]") {
            list = line[open.upperBound..<close]
        } else {
            return
        }
        capabilities = Set(list.split(separator: " ").map(String.init))
    }

    /// "… {123}\r\n" → 123
    private func trailingLiteralSize(of line: Data) -> Int? {
        // Strip CRLF.
        var content = line
        while let last = content.last, last == 13 || last == 10 {
            content.removeLast()
        }
        guard content.last == UInt8(ascii: "}"),
              let open = content.lastIndex(of: UInt8(ascii: "{"))
        else { return nil }
        let digits = content[content.index(after: open)..<content.index(before: content.endIndex)]
        return Int(String(decoding: digits, as: UTF8.self))
    }

    /// IMAP quoted string: escape backslash and double quote.
    private func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
