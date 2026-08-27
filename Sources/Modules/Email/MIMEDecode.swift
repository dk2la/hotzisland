import Foundation

/// Pure MIME/RFC822 decoding helpers: encoded-word headers, transfer
/// encodings, charsets, dates, header blocks. No I/O — unit-testable.
enum MIMEDecode {
    // MARK: - Charsets

    static func encoding(forCharset name: String) -> String.Encoding {
        switch name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")) {
        case "utf-8", "utf8", "us-ascii", "ascii": .utf8
        case "iso-8859-1", "latin1", "latin-1": .isoLatin1
        case "iso-8859-5": .isoLatin1 // closest lossless byte mapping we ship
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

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        default: nil
        }
    }

    /// Byte-level quoted-printable: "=XX" escapes and "=\r\n" soft breaks.
    /// Works on bytes so the charset decision stays with the caller.
    static func decodeQuotedPrintable(_ raw: Data) -> Data {
        var out = Data()
        var index = raw.startIndex
        while index < raw.endIndex {
            let byte = raw[index]
            guard byte == UInt8(ascii: "=") else {
                out.append(byte)
                index = raw.index(after: index)
                continue
            }
            let next = raw.index(after: index)
            guard next < raw.endIndex else { out.append(byte); break }
            if raw[next] == 13 { // soft break "=\r\n" (or a lone "=\r")
                let after = raw.index(after: next)
                index = (after < raw.endIndex && raw[after] == 10) ? raw.index(after: after) : after
                continue
            }
            if raw[next] == 10 { // soft break "=\n"
                index = raw.index(after: next)
                continue
            }
            let second = raw.index(after: next)
            if second < raw.endIndex,
               let high = hexValue(raw[next]),
               let low = hexValue(raw[second]) {
                out.append(high << 4 | low)
                index = raw.index(after: second)
                continue
            }
            out.append(byte) // stray "=" — keep it verbatim
            index = next
        }
        return out
    }

    static func decodeQuotedPrintable(_ text: String, charset: String) -> String {
        // Latin-1 keeps every scalar below 256 as one byte, so the charset
        // decode below sees the original octets.
        let bytes = text.data(using: .isoLatin1) ?? Data(text.utf8)
        return string(from: decodeQuotedPrintable(bytes), charset: charset)
    }

    static func decodeBase64Text(_ text: String, charset: String) -> String {
        guard let data = Data(base64Encoded: Data(text.utf8), options: .ignoreUnknownCharacters) else {
            return text
        }
        return string(from: data, charset: charset)
    }

    /// Decodes a body payload according to its Content-Transfer-Encoding.
    static func decodeBody(_ raw: Data, encoding: String, charset: String) -> String {
        switch encoding.lowercased().trimmingCharacters(in: .whitespaces) {
        case "base64":
            let data = Data(base64Encoded: raw, options: .ignoreUnknownCharacters) ?? raw
            return string(from: data, charset: charset)
        case "quoted-printable":
            return string(from: decodeQuotedPrintable(raw), charset: charset)
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

    // MARK: - Header blocks

    /// Splits a raw RFC 5322 header block into unfolded lowercased-name →
    /// value pairs. The first occurrence of a name wins.
    static func parseHeaders(_ raw: Data) -> [String: String] {
        let text = String(data: raw, encoding: .isoLatin1) ?? String(decoding: raw, as: UTF8.self)
        var headers: [String: String] = [:]
        var name: String?
        var value = ""

        func commit() {
            if let name, headers[name] == nil {
                headers[name] = decodeEncodedWords(value.trimmingCharacters(in: .whitespaces))
            }
            value = ""
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
            if line.isEmpty { break } // end of the header block
            if line.first == " " || line.first == "\t" {
                value += " " + line.trimmingCharacters(in: .whitespaces) // folded continuation
                continue
            }
            commit()
            guard let colon = line.firstIndex(of: ":") else { name = nil; continue }
            name = line[..<colon].lowercased().trimmingCharacters(in: .whitespaces)
            value = String(line[line.index(after: colon)...])
        }
        commit()
        return headers
    }

    /// Reads a parameter off a structured header value, e.g. the "utf-8" of
    /// `text/plain; charset="utf-8"`.
    static func parameter(_ name: String, in headerValue: String) -> String? {
        for piece in headerValue.split(separator: ";").dropFirst() {
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            guard trimmed[..<equals].lowercased() == name.lowercased() else { continue }
            return trimmed[trimmed.index(after: equals)...]
                .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        }
        return nil
    }

    /// The bare type of a Content-Type value: "text/plain; charset=x" → "text/plain".
    static func mediaType(of headerValue: String) -> String {
        (headerValue.split(separator: ";").first.map(String.init) ?? headerValue)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    // MARK: - Raw body → readable text

    private struct TextCandidate {
        var text: String
        var isPlain: Bool
    }

    /// Extracts readable text from a raw MIME body, walking multipart
    /// containers and preferring text/plain over text/html. Used as the
    /// fallback when BODYSTRUCTURE gave us no usable text part.
    static func extractText(rawBody: Data, contentType: String, transferEncoding: String) -> String {
        candidate(rawBody: rawBody, contentType: contentType, transferEncoding: transferEncoding)?.text ?? ""
    }

    private static func candidate(
        rawBody: Data,
        contentType: String,
        transferEncoding: String
    ) -> TextCandidate? {
        let type = mediaType(of: contentType)
        if type.hasPrefix("multipart/") {
            guard let boundary = parameter("boundary", in: contentType) else { return nil }
            var htmlFallback: TextCandidate?
            for part in splitParts(rawBody, boundary: boundary) {
                let (headerData, bodyData) = splitHeaderAndBody(part)
                let headers = parseHeaders(headerData)
                guard let found = candidate(
                    rawBody: bodyData,
                    contentType: headers["content-type"] ?? "text/plain",
                    transferEncoding: headers["content-transfer-encoding"] ?? "7bit"
                ), !found.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                if found.isPlain { return found }
                htmlFallback = htmlFallback ?? found
            }
            return htmlFallback
        }
        guard type.hasPrefix("text/") || type.isEmpty else { return nil } // skip attachments
        let charset = parameter("charset", in: contentType) ?? "utf-8"
        let decoded = decodeBody(rawBody, encoding: transferEncoding, charset: charset)
        return type == "text/html"
            ? TextCandidate(text: htmlToPlainText(decoded), isPlain: false)
            : TextCandidate(text: decoded, isPlain: true)
    }

    /// Splits a multipart body on its "--boundary" delimiters.
    static func splitParts(_ data: Data, boundary: String) -> [Data] {
        let delimiter = Data("--\(boundary)".utf8)
        var starts: [Range<Data.Index>] = []
        var cursor = data.startIndex
        while cursor < data.endIndex, let found = data[cursor...].range(of: delimiter) {
            starts.append(found)
            cursor = found.upperBound
        }
        guard starts.count >= 2 else { return [] }
        var parts: [Data] = []
        for (offset, marker) in starts.enumerated() where offset + 1 < starts.count {
            var start = marker.upperBound
            if start < data.endIndex, data[start] == 13 { start = data.index(after: start) }
            if start < data.endIndex, data[start] == 10 { start = data.index(after: start) }
            var end = starts[offset + 1].lowerBound
            // Drop the CRLF that belongs to the following delimiter line.
            if end > start, data[data.index(before: end)] == 10 { end = data.index(before: end) }
            if end > start, data[data.index(before: end)] == 13 { end = data.index(before: end) }
            if end > start { parts.append(Data(data[start..<end])) }
        }
        return parts
    }

    /// Splits one MIME entity into its header block and its body.
    static func splitHeaderAndBody(_ data: Data) -> (Data, Data) {
        if let range = data.range(of: Data([13, 10, 13, 10])) {
            return (Data(data[..<range.lowerBound]), Data(data[range.upperBound...]))
        }
        if let range = data.range(of: Data([10, 10])) {
            return (Data(data[..<range.lowerBound]), Data(data[range.upperBound...]))
        }
        return (data, Data())
    }

    // MARK: - HTML → text

    private static let entities = [
        "&nbsp;": "\u{00A0}", "&amp;": "&", "&lt;": "<", "&gt;": ">",
        "&quot;": "\"", "&apos;": "'", "&#39;": "'", "&mdash;": "—",
        "&ndash;": "–", "&hellip;": "…", "&laquo;": "«", "&raquo;": "»",
        "&rsquo;": "'", "&zwnj;": "",
    ]

    /// Flattens HTML mail into readable text: drops script/style, turns block
    /// tags into line breaks, strips the rest, resolves common entities.
    static func htmlToPlainText(_ html: String) -> String {
        var text = html
        for tag in ["script", "style", "head"] {
            while let open = text.range(of: "<\(tag)", options: .caseInsensitive),
                  let close = text.range(of: "</\(tag)>", options: .caseInsensitive, range: open.upperBound..<text.endIndex) {
                text.removeSubrange(open.lowerBound..<close.upperBound)
            }
        }
        for breakTag in ["<br>", "<br/>", "<br />", "</p>", "</div>", "</tr>", "</li>", "</h1>", "</h2>", "</h3>"] {
            text = text.replacingOccurrences(of: breakTag, with: "\n", options: .caseInsensitive)
        }

        var stripped = ""
        var depth = 0
        for character in text {
            if character == "<" {
                depth += 1
            } else if character == ">" {
                depth = max(0, depth - 1)
            } else if depth == 0 {
                stripped.append(character)
            }
        }

        for (entity, replacement) in entities {
            stripped = stripped.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        stripped = decodeNumericEntities(stripped)

        // Collapse the whitespace HTML source is padded with.
        let lines = stripped
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var result: [String] = []
        for line in lines {
            if line.isEmpty, result.last?.isEmpty ?? true { continue }
            result.append(line)
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeNumericEntities(_ text: String) -> String {
        guard text.contains("&#") else { return text }
        var result = ""
        var rest = Substring(text)
        while let start = rest.range(of: "&#") {
            result += rest[..<start.lowerBound]
            rest = rest[start.upperBound...]
            guard let end = rest.firstIndex(of: ";") else { result += "&#"; break }
            let body = rest[..<end]
            let isHex = body.first == "x" || body.first == "X"
            let digits = isHex ? body.dropFirst() : body
            if let code = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                result.append(Character(scalar))
            } else {
                result += "&#" + body + ";"
            }
            rest = rest[rest.index(after: end)...]
        }
        result += rest
        return result
    }

    // MARK: - Dates

    /// Shared with MailComposer so the compose and parse sides of the wire
    /// format cannot drift apart.
    static let rfc5322DateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

    private static let dateFormats = [
        rfc5322DateFormat,
        "dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm Z",
        "dd MMM yyyy HH:mm Z",
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
