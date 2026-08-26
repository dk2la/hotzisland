import Foundation

/// A parsed IMAP value: atoms, strings (quoted or literal), nested lists.
/// `nilValue` is spelled out rather than `none` so it can never collide with
/// `Optional.none` at a `IMAPValue?` return site.
indirect enum IMAPValue: Equatable, Sendable {
    case atom(String)
    case string(Data)
    case list([IMAPValue])
    case nilValue // NIL

    var text: String? {
        switch self {
        case .atom(let s): s
        case .string(let d): String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1)
        case .list, .nilValue: nil
        }
    }

    var items: [IMAPValue]? {
        if case .list(let values) = self { return values }
        return nil
    }

    var isList: Bool {
        if case .list = self { return true }
        return false
    }

    var number: UInt32? {
        text.flatMap(UInt32.init)
    }
}

/// Pure parser over one complete response unit (a line with its `{n}`
/// literals already appended). No I/O — unit-testable against fixtures.
enum IMAPParser {
    // MARK: - Tokenizer / value parser

    /// Parses the remainder of a FETCH-style line into values. `data` must
    /// contain the full unit including literal payloads inline.
    static func parseValues(_ data: Data) -> [IMAPValue] {
        var index = data.startIndex
        var values: [IMAPValue] = []
        while let value = parseValue(data, &index) {
            values.append(value)
        }
        return values
    }

    private static func skipSpaces(_ data: Data, _ index: inout Data.Index) {
        while index < data.endIndex, data[index] == UInt8(ascii: " ") {
            index = data.index(after: index)
        }
    }

    private static func parseValue(_ data: Data, _ index: inout Data.Index) -> IMAPValue? {
        skipSpaces(data, &index)
        guard index < data.endIndex else { return nil }
        let byte = data[index]
        switch byte {
        case UInt8(ascii: "("):
            index = data.index(after: index)
            var items: [IMAPValue] = []
            while true {
                skipSpaces(data, &index)
                guard index < data.endIndex else { break }
                if data[index] == UInt8(ascii: ")") {
                    index = data.index(after: index)
                    break
                }
                guard let item = parseValue(data, &index) else { break }
                items.append(item)
            }
            return .list(items)
        case UInt8(ascii: ")"):
            return nil
        case UInt8(ascii: "\""):
            index = data.index(after: index)
            var bytes = Data()
            while index < data.endIndex {
                let b = data[index]
                if b == UInt8(ascii: "\\"), data.index(after: index) < data.endIndex {
                    index = data.index(after: index)
                    bytes.append(data[index])
                } else if b == UInt8(ascii: "\"") {
                    index = data.index(after: index)
                    break
                } else {
                    bytes.append(b)
                }
                index = data.index(after: index)
            }
            return .string(bytes)
        case UInt8(ascii: "{"):
            // Literal: {n}\r\n followed by exactly n raw bytes.
            guard let close = data[index...].firstIndex(of: UInt8(ascii: "}")) else { return nil }
            let numberBytes = data[data.index(after: index)..<close]
            guard let count = Int(String(decoding: numberBytes, as: UTF8.self)) else { return nil }
            var cursor = data.index(after: close)
            // Skip CRLF after the size.
            if cursor < data.endIndex, data[cursor] == UInt8(ascii: "\r") { cursor = data.index(after: cursor) }
            if cursor < data.endIndex, data[cursor] == UInt8(ascii: "\n") { cursor = data.index(after: cursor) }
            let end = data.index(cursor, offsetBy: count, limitedBy: data.endIndex) ?? data.endIndex
            let payload = data[cursor..<end]
            index = end
            return .string(Data(payload))
        default:
            // Atom: up to space, paren, or line end. Brackets suspend that —
            // "BODY[HEADER.FIELDS (SUBJECT FROM)]" is one key, not three.
            var bytes = Data()
            var brackets = 0
            while index < data.endIndex {
                let b = data[index]
                if b == UInt8(ascii: "[") {
                    brackets += 1
                } else if b == UInt8(ascii: "]") {
                    brackets = max(0, brackets - 1)
                } else if brackets == 0 {
                    if b == UInt8(ascii: " ") || b == UInt8(ascii: "(") || b == UInt8(ascii: ")")
                        || b == UInt8(ascii: "\r") || b == UInt8(ascii: "\n") {
                        break
                    }
                }
                bytes.append(b)
                index = data.index(after: index)
            }
            let text = String(decoding: bytes, as: UTF8.self)
            if text.isEmpty { return nil }
            if text.uppercased() == "NIL" { return IMAPValue.nilValue }
            return .atom(text)
        }
    }

    // MARK: - FETCH extraction

    struct FetchItem {
        var uid: UInt32?
        var flags: [String] = []
        var internalDate: Date?
        var envelope: Envelope?
        var textPart: EmailMessage.TextPartInfo?
        /// BODY[…] payloads keyed by the section inside the brackets.
        var bodyPayloads: [String: Data] = [:]
    }

    struct Envelope {
        var date: Date?
        var subject: String
        var fromName: String
        var fromAddress: String
        var messageID: String?
        var inReplyTo: String?
    }

    /// Parses one `* n FETCH (…)` unit. Returns nil for non-FETCH units.
    static func parseFetch(_ unit: Data) -> FetchItem? {
        guard let listStart = unit.firstIndex(of: UInt8(ascii: "(")) else { return nil }
        let header = String(decoding: unit[..<listStart], as: UTF8.self).uppercased()
        guard header.contains(" FETCH") else { return nil }
        var index = listStart
        guard let value = parseValue(unit, &index), let pairs = value.items else { return nil }

        var item = FetchItem()
        var cursor = 0
        while cursor + 1 <= pairs.count - 1 {
            guard case .atom(let rawKey) = pairs[cursor] else { cursor += 1; continue }
            let key = rawKey.uppercased()
            let payload = pairs[cursor + 1]
            switch key {
            case "UID":
                item.uid = payload.number
            case "FLAGS":
                item.flags = payload.items?.compactMap(\.text) ?? []
            case "INTERNALDATE":
                item.internalDate = payload.text.flatMap(MIMEDecode.parseDate)
            case "ENVELOPE":
                item.envelope = parseEnvelope(payload)
            case "BODYSTRUCTURE", "BODY":
                if payload.isList {
                    item.textPart = findTextPart(payload, path: [])
                }
            default:
                // BODY[…] payloads: the section lives inside the brackets.
                if key.hasPrefix("BODY["),
                   let open = key.firstIndex(of: "["),
                   let close = key.lastIndex(of: "]"),
                   case .string(let data) = payload {
                    item.bodyPayloads[String(key[key.index(after: open)..<close])] = data
                }
            }
            cursor += 2
        }
        return item
    }

    private static func decodedText(_ value: IMAPValue) -> String {
        switch value {
        case .atom(let s): MIMEDecode.decodeEncodedWords(s)
        case .string(let d):
            MIMEDecode.decodeEncodedWords(
                String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1) ?? ""
            )
        case .list, .nilValue: ""
        }
    }

    private static func parseEnvelope(_ value: IMAPValue) -> Envelope? {
        guard let fields = value.items, fields.count >= 10 else { return nil }
        // (date subject from sender reply-to to cc bcc in-reply-to message-id)
        var envelope = Envelope(subject: "", fromName: "", fromAddress: "")
        envelope.date = fields[0].text.flatMap(MIMEDecode.parseDate)
        envelope.subject = decodedText(fields[1])
        if let fromList = fields[2].items, let first = fromList.first?.items, first.count >= 4 {
            // address = (name adl mailbox host)
            envelope.fromName = decodedText(first[0])
            let mailbox = first[2].text ?? ""
            let host = first[3].text ?? ""
            envelope.fromAddress = host.isEmpty ? mailbox : "\(mailbox)@\(host)"
            if envelope.fromName.isEmpty {
                envelope.fromName = envelope.fromAddress
            }
        }
        envelope.inReplyTo = fields[8].text
        envelope.messageID = fields[9].text
        return envelope
    }

    /// Picks the part to show for a message: the first text/plain leaf, or
    /// the first text/html one when the sender shipped HTML only.
    static func findTextPart(_ value: IMAPValue, path: [Int]) -> EmailMessage.TextPartInfo? {
        var found: [EmailMessage.TextPartInfo] = []
        collectTextParts(value, path: path, into: &found)
        return found.first { !$0.isHTML } ?? found.first
    }

    /// Walks a BODYSTRUCTURE, tracking the IMAP section path ("1", "1.2", …).
    /// A non-multipart message is section "1".
    private static func collectTextParts(
        _ value: IMAPValue,
        path: [Int],
        into result: inout [EmailMessage.TextPartInfo]
    ) {
        guard let items = value.items, items.count >= 2 else { return }
        if items[0].isList {
            // Multipart: child parts first, then the subtype atom.
            for (offset, child) in items.enumerated() {
                guard child.isList else { break }
                collectTextParts(child, path: path + [offset + 1], into: &result)
            }
            return
        }
        guard let type = items[0].text?.uppercased(),
              let subtype = items[1].text?.uppercased()
        else { return }

        // An embedded message: its parts are numbered under this one.
        if type == "MESSAGE", subtype == "RFC822", items.count >= 9 {
            let nested = items[8]
            let nestedIsMultipart = nested.items?.first?.isList ?? false
            collectTextParts(nested, path: nestedIsMultipart ? path : path + [1], into: &result)
            return
        }

        // Leaf: ("TEXT" "PLAIN" ("CHARSET" "UTF-8" …) id desc encoding size lines md5 disposition …)
        guard type == "TEXT", subtype == "PLAIN" || subtype == "HTML", items.count >= 7 else { return }
        if items.count >= 10, items[9].items?.first?.text?.uppercased() == "ATTACHMENT" {
            return // a .txt/.html file riding along, not the message body
        }
        var charset = "utf-8"
        if let params = items[2].items {
            var index = 0
            while index + 1 < params.count {
                if params[index].text?.uppercased() == "CHARSET",
                   let value = params[index + 1].text {
                    charset = value
                }
                index += 2
            }
        }
        result.append(EmailMessage.TextPartInfo(
            section: path.isEmpty ? "1" : path.map(String.init).joined(separator: "."),
            encoding: items[5].text ?? "7bit",
            charset: charset,
            isHTML: subtype == "HTML"
        ))
    }

    // MARK: - Other responses

    /// "* SEARCH 4 8 15" → [4, 8, 15]
    static func parseSearch(_ unit: Data) -> [UInt32]? {
        // Trim first: the trailing CRLF would otherwise swallow the last UID.
        let text = String(decoding: unit, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.uppercased().hasPrefix("* SEARCH") else { return nil }
        return text.split(separator: " ").dropFirst(2).compactMap { UInt32($0) }
    }

    /// "* 231 EXISTS" → 231
    static func parseExists(_ unit: Data) -> Int? {
        let text = String(decoding: unit, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let parts = text.split(separator: " ")
        guard parts.count >= 3, parts[0] == "*", parts[2].hasPrefix("EXISTS") else { return nil }
        return Int(parts[1])
    }
}
