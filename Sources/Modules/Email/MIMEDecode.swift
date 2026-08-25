import Foundation

/// Pure MIME/RFC822 decoding helpers: encoded-word headers, transfer
/// encodings, charsets, dates. No I/O — unit-testable.
enum MIMEDecode {
    // MARK: - Charsets

    static func encoding(forCharset name: String) -> String.Encoding {
        switch name.lowercased() {
        case "utf-8", "utf8", "us-ascii", "ascii": .utf8
        case "iso-8859-1", "latin1", "latin-1": .isoLatin1
        case "windows-1251", "cp1251": .windowsCP1251
        case "windows-1252", "cp1252": .windowsCP1252
        case "koi8-r": String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.KOI8_R.rawValue)))
        default: .utf8
        }
    }

    static func string(from data: Data, charset: String) -> String {
        if let text = String(data: data, encoding: encoding(forCharset: charset)) {
            return text
        }
        // Fallback chain: UTF-8 → Latin-1 (never fails).
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    // MARK: - Transfer encodings

    static func decodeQuotedPrintable(_ text: String, charset: String = "utf-8") -> String {
        var data = Data()
        var iterator = text.unicodeScalars.makeIterator()
        var pending: [UnicodeScalar] = []
        // Collect scalars so we can look ahead for soft line breaks.
        while let scalar = iterator.next() {
            pending.append(scalar)
        }
        var index = 0
        while index < pending.count {
            let scalar = pending[index]
            if scalar == "=" {
                // Soft break "=\r\n" or "=\n" — swallow.
                if index + 2 < pending.count, pending[index + 1] == "\r", pending[index + 2] == "\n" {
                    index += 3
                    continue
                }
                if index + 1 < pending.count, pending[index + 1] == "\n" {
                    index += 2
                    continue
                }
                if index + 2 < pending.count,
                   let hi = Character(pending[index + 1]).hexDigitValue,
                   let lo = Character(pending[index + 2]).hexDigitValue {
                    data.append(UInt8(hi * 16 + lo))
                    index += 3
                    continue
                }
            }
            data.append(contentsOf: String(scalar).utf8)
            index += 1
        }
        return string(from: data, charset: charset)
    }

    static func decodeBase64Text(_ text: String, charset: String) -> String {
        let cleaned = text.filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: cleaned) else { return text }
        return string(from: data, charset: charset)
    }

    /// Decodes a body payload according to its Content-Transfer-Encoding.
    static func decodeBody(_ raw: Data, encoding: String, charset: String) -> String {
        switch encoding.lowercased() {
        case "base64":
            let cleaned = String(data: raw, encoding: .ascii)?.filter { !$0.isWhitespace } ?? ""
            let data = Data(base64Encoded: cleaned) ?? raw
            return string(from: data, charset: charset)
        case "quoted-printable":
            let text = String(data: raw, encoding: .ascii) ?? string(from: raw, charset: charset)
            return decodeQuotedPrintable(text, charset: charset)
        default:
            return string(from: raw, charset: charset)
        }
    }

    // MARK: - RFC 2047 encoded words

    /// Decodes "=?charset?B|Q?payload?=" runs; whitespace between two
    /// adjacent encoded words is dropped per spec.
    static func decodeEncodedWords(_ header: String) -> String {
        guard header.contains("=?") else { return header }
        var result = ""
        var rest = Substring(header)
        var lastWasEncoded = false
        var pendingSpace = ""

        while let start = rest.range(of: "=?") {
            let before = rest[..<start.lowerBound]
            // Whitespace between adjacent encoded words disappears.
            if lastWasEncoded, before.allSatisfy(\.isWhitespace) {
                // drop
            } else {
                result += pendingSpace + before
            }
            pendingSpace = ""
            rest = rest[start.upperBound...]

            guard let charsetEnd = rest.firstIndex(of: "?") else {
                result += "=?"
                break
            }
            let charset = String(rest[..<charsetEnd])
            var cursor = rest.index(after: charsetEnd)
            guard cursor < rest.endIndex else { result += "=?" + charset + "?"; break }
            let kind = Character(rest[cursor].lowercased())
            cursor = rest.index(after: cursor)
            guard cursor < rest.endIndex, rest[cursor] == "?" else {
                result += "=?" + charset + "?"
                continue
            }
            cursor = rest.index(after: cursor)
            guard let end = rest[cursor...].range(of: "?=") else {
                result += "=?" + rest[rest.startIndex...]
                rest = rest[rest.endIndex...]
                break
            }
            let payload = String(rest[cursor..<end.lowerBound])
            let decoded: String
            switch kind {
            case "b":
                decoded = decodeBase64Text(payload, charset: charset)
            case "q":
                // Q-encoding: underscore is space.
                decoded = decodeQuotedPrintable(
                    payload.replacingOccurrences(of: "_", with: " "),
                    charset: charset
                )
            default:
                decoded = payload
            }
            result += decoded
            rest = rest[end.upperBound...]
            lastWasEncoded = true
        }
        result += pendingSpace + rest
        return result
    }

    // MARK: - Dates

    private static let dateFormats = [
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm Z",
        "dd-MMM-yyyy HH:mm:ss Z", // IMAP INTERNALDATE
    ]

    static func parseDate(_ raw: String) -> Date? {
        // Strip a trailing "(UTC)"-style comment.
        var text = raw
        if let paren = text.firstIndex(of: "(") {
            text = String(text[..<paren])
        }
        text = text.trimmingCharacters(in: .whitespaces)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in dateFormats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return date
            }
        }
        return nil
    }
}
