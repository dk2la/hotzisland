import Foundation

/// Builds the RFC 5322 message an SMTP DATA command carries. Pure — the
/// message id and date are injected so the output is testable.
enum MailComposer {
    static let domain = "hotzisland"

    static func messageID(_ uuid: UUID = UUID()) -> String {
        "<\(uuid.uuidString.lowercased())@\(domain)>"
    }

    /// The body goes out base64: it keeps UTF-8 intact and no encoded line
    /// can begin with a dot, so SMTP dot-stuffing never comes into play.
    static func rfc5322(_ mail: OutgoingMail, messageID: String, date: Date) -> String {
        var headers: [(String, String)] = [
            ("From", mail.from),
            ("To", mail.to),
            ("Subject", encodeHeader(mail.subject)),
            ("Date", rfc5322Date(date)),
            ("Message-ID", messageID),
        ]
        if let inReplyTo = mail.inReplyTo {
            headers.append(("In-Reply-To", inReplyTo))
        }
        // Threading: the parent's chain plus the parent itself.
        var chain = mail.references
        if let inReplyTo = mail.inReplyTo, chain.last != inReplyTo {
            chain.append(inReplyTo)
        }
        if !chain.isEmpty {
            headers.append(("References", fold(chain.joined(separator: " "))))
        }
        headers.append(contentsOf: [
            ("MIME-Version", "1.0"),
            ("Content-Type", "text/plain; charset=utf-8"),
            ("Content-Transfer-Encoding", "base64"),
        ])

        let head = headers.map { "\($0.0): \($0.1)" }.joined(separator: "\r\n")
        let body = Data(mail.body.utf8).base64EncodedString(
            options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed]
        )
        return head + "\r\n\r\n" + body + (body.hasSuffix("\r\n") ? "" : "\r\n")
    }

    static func rfc5322(_ mail: OutgoingMail) -> String {
        rfc5322(mail, messageID: messageID(), date: Date())
    }

    /// "Re: " added once, whatever case the original used.
    static func replySubject(_ subject: String) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("re:") { return trimmed }
        return trimmed.isEmpty ? "Re:" : "Re: \(trimmed)"
    }

    // MARK: - Header encoding

    /// RFC 2047 base64 encoded words, chunked so no line runs past 75 chars.
    static func encodeHeader(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { $0.value > 127 }) else { return text }
        var words: [String] = []
        var chunk = ""
        for character in text {
            // 45 UTF-8 bytes encode to 60 base64 chars, leaving room for the
            // "=?UTF-8?B?…?=" wrapper inside the 75-char limit.
            if chunk.utf8.count + String(character).utf8.count > 45 {
                words.append(encodedWord(chunk))
                chunk = ""
            }
            chunk.append(character)
        }
        if !chunk.isEmpty { words.append(encodedWord(chunk)) }
        return words.joined(separator: "\r\n ")
    }

    private static func encodedWord(_ text: String) -> String {
        "=?UTF-8?B?\(Data(text.utf8).base64EncodedString())?="
    }

    /// Folds a long structured value onto continuation lines.
    private static func fold(_ value: String) -> String {
        var lines: [String] = []
        var current = ""
        for token in value.split(separator: " ") {
            if !current.isEmpty, current.count + token.count + 1 > 76 {
                lines.append(current)
                current = ""
            }
            current += current.isEmpty ? String(token) : " \(token)"
        }
        if !current.isEmpty { lines.append(current) }
        return lines.joined(separator: "\r\n ")
    }

    static func rfc5322Date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = MIMEDecode.rfc5322DateFormat
        return formatter.string(from: date)
    }
}
