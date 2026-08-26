import Foundation
import OSLog

/// Minimal IMAP4rev1 client scoped to one INBOX session: login, unseen
/// search, header fetch, body fetch, mark seen. Stateless by design — the
/// service opens a fresh session per refresh.
actor IMAPClient {
    private let transport: TLSTransport
    private var tagCounter = 0
    private let log = Logger(subsystem: "com.dk2la.hotzisland", category: "email")
    /// Cap for the structure-free body fetch (256 KB).
    private static let bodyByteLimit = 262_144

    init(host: String, port: UInt16) {
        transport = TLSTransport(host: host, port: port)
    }

    // MARK: - Session

    func connect() async throws {
        try await transport.connect()
        // Server greeting: "* OK ..."
        let greeting = try await transport.readLine()
        let text = String(decoding: greeting, as: UTF8.self)
        guard text.uppercased().contains("OK") else {
            throw MailError.badResponse(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
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

    func searchUnseenCount() async throws -> Int {
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
        var messages: [EmailMessage] = []
        for unit in units {
            guard let item = IMAPParser.parseFetch(unit), let uid = item.uid else { continue }
            let envelope = item.envelope
            messages.append(EmailMessage(
                uid: uid,
                subject: envelope?.subject ?? "",
                fromName: envelope?.fromName ?? "",
                fromAddress: envelope?.fromAddress ?? "",
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
                let text = part.isHTML ? MIMEDecode.htmlToPlainText(decoded) : decoded
                log.info("body uid=\(uid, privacy: .public) section=\(part.section, privacy: .public) enc=\(part.encoding, privacy: .public) chars=\(text.count, privacy: .public)")
                return MessageBody(text: text, references: Self.references(in: item))
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
            let text = MIMEDecode.extractText(
                rawBody: body,
                contentType: headers["content-type"] ?? "text/plain",
                transferEncoding: headers["content-transfer-encoding"] ?? "7bit"
            )
            log.info("body fallback uid=\(uid, privacy: .public) bytes=\(body.count, privacy: .public) chars=\(text.count, privacy: .public)")
            return MessageBody(text: text, references: Self.references(in: item))
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

    func markSeen(uid: UInt32) async throws {
        _ = try await command("UID STORE \(uid) +FLAGS.SILENT (\\Seen)")
    }

    func logout() async {
        _ = try? await command("LOGOUT")
        await transport.close()
    }

    // MARK: - Wire protocol

    /// Sends one tagged command and gathers complete response units (each a
    /// line with any `{n}` literals inlined) until the tagged completion.
    private func command(_ text: String) async throws -> [Data] {
        tagCounter += 1
        let tag = "A\(tagCounter)"
        try await transport.send(Data("\(tag) \(text)\r\n".utf8))

        var units: [Data] = []
        while true {
            let unit = try await readUnit()
            let line = String(decoding: unit.prefix(200), as: UTF8.self)
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
    private func readUnit() async throws -> Data {
        var unit = Data()
        while true {
            let line = try await transport.readLine()
            unit.append(line)
            guard let size = trailingLiteralSize(of: line) else {
                return unit
            }
            let payload = try await transport.read(exactly: size)
            unit.append(payload)
        }
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
