import XCTest

final class MIMEDecodeTests: XCTestCase {
    // MARK: - Headers

    func testEncodedWords() {
        XCTAssertEqual(MIMEDecode.decodeEncodedWords("=?UTF-8?B?0J/RgNC40LLQtdGC?="), "Привет")
        // Whitespace between two adjacent encoded words disappears per RFC 2047.
        XCTAssertEqual(MIMEDecode.decodeEncodedWords("=?UTF-8?B?0J/RgNC4?= =?UTF-8?B?0LLQtdGC?="), "Привет")
        XCTAssertEqual(MIMEDecode.decodeEncodedWords("=?utf-8?Q?Hello_=D0=BC=D0=B8=D1=80?="), "Hello мир")
        XCTAssertEqual(MIMEDecode.decodeEncodedWords("=?windows-1251?Q?=CF=F0=E8=E2=E5=F2?="), "Привет")
        XCTAssertEqual(MIMEDecode.decodeEncodedWords("Re: =?UTF-8?B?0J/RgNC40LLQtdGC?= (fwd)"), "Re: Привет (fwd)")
        XCTAssertEqual(MIMEDecode.decodeEncodedWords("Plain subject"), "Plain subject")
    }

    /// A broken encoded word is emitted verbatim exactly once — earlier the
    /// bail-outs re-appended the charset ("=?UTF-8?" became "=?UTF-8?UTF-8?").
    func testMalformedEncodedWordPassesThroughOnce() {
        XCTAssertEqual(MIMEDecode.decodeEncodedWords("=?UTF-8?"), "=?UTF-8?")
        XCTAssertEqual(MIMEDecode.decodeEncodedWords("=?UTF-8?B"), "=?UTF-8?B")
        XCTAssertEqual(MIMEDecode.decodeEncodedWords("=?UTF-8?Bx"), "=?UTF-8?Bx")
        XCTAssertEqual(MIMEDecode.decodeEncodedWords("Re: =?UTF-8?B?0J/RgNC4 (fwd)"), "Re: =?UTF-8?B?0J/RgNC4 (fwd)")
        XCTAssertEqual(MIMEDecode.decodeEncodedWords("=?"), "=?")
        // A good word after a broken one still decodes.
        XCTAssertEqual(MIMEDecode.decodeEncodedWords("=?UTF-8? =?UTF-8?B?0J/RgNC40LLQtdGC?="), "=?UTF-8? Привет")
    }

    func testUnpaddedBase64EncodedWord() {
        XCTAssertEqual(MIMEDecode.decodeEncodedWords("=?UTF-8?B?SGk?="), "Hi") // "SGk=" minus the padding
        XCTAssertEqual(MIMEDecode.decodeEncodedWords("=?UTF-8?B?0J/RgNC40LLQtdGCIQ?="), "Привет!") // "…IQ=="
    }

    func testHeaderBlockUnfolding() {
        let raw = Data("Subject: =?UTF-8?B?0J/RgNC40LLQtdGC?=\r\nContent-Type: text/plain;\r\n\tcharset=\"koi8-r\"\r\n\r\nbody\r\n".utf8)
        let headers = MIMEDecode.parseHeaders(raw)
        XCTAssertEqual(headers["subject"], "Привет")
        XCTAssertEqual(headers["content-type"], "text/plain; charset=\"koi8-r\"")
        XCTAssertEqual(MIMEDecode.parameter("charset", in: headers["content-type"] ?? ""), "koi8-r")
        XCTAssertEqual(MIMEDecode.mediaType(of: headers["content-type"] ?? ""), "text/plain")
    }

    // MARK: - Transfer encodings

    func testBase64BodyIgnoresLineWrapping() {
        let source = "[image: Google]\r\nПривет"
        let encoded = Data(source.utf8).base64EncodedString()
        let wrapped = encoded.prefix(8) + "\r\n" + encoded.dropFirst(8)
        XCTAssertEqual(MIMEDecode.decodeBody(Data(wrapped.utf8), encoding: "base64", charset: "utf-8"), source)
    }

    func testQuotedPrintableSoftBreaksAndCharset() {
        XCTAssertEqual(
            MIMEDecode.decodeBody(Data("Hello=20=D0=BC=D0=B8=D1=80=\r\n!".utf8), encoding: "quoted-printable", charset: "utf-8"),
            "Hello мир!"
        )
        // High bytes must reach the charset decoder as single octets.
        XCTAssertEqual(
            MIMEDecode.decodeBody(Data("=CF=F0=E8=E2=E5=F2".utf8), encoding: "quoted-printable", charset: "windows-1251"),
            "Привет"
        )
    }

    // MARK: - Charsets

    /// Cyrillic 8-bit charsets must reach their real decoder — ISO-8859-5
    /// used to be aliased to Latin-1 and came out as mojibake.
    func testCyrillicCharsets() {
        let iso8859_5 = Data([0xBF, 0xE0, 0xD8, 0xD2, 0xD5, 0xE2]) // "Привет"
        XCTAssertEqual(MIMEDecode.decodeBody(iso8859_5, encoding: "8bit", charset: "iso-8859-5"), "Привет")
        XCTAssertEqual(MIMEDecode.decodeBody(iso8859_5, encoding: "8bit", charset: "\"ISO-8859-5\""), "Привет")
        let koi8r = Data([0xF0, 0xD2, 0xC9, 0xD7, 0xC5, 0xD4]) // "Привет"
        XCTAssertEqual(MIMEDecode.decodeBody(koi8r, encoding: "8bit", charset: "koi8-r"), "Привет")
        XCTAssertEqual(MIMEDecode.decodeBody(koi8r, encoding: "8bit", charset: "KOI8-U"), "Привет")
        // An unknown charset name still yields text (UTF-8, then Latin-1).
        XCTAssertEqual(MIMEDecode.decodeBody(Data("Привет".utf8), encoding: "8bit", charset: "x-no-such-charset"), "Привет")
        XCTAssertEqual(MIMEDecode.decodeBody(Data([0xE9]), encoding: "8bit", charset: "x-no-such-charset"), "é")
    }

    // MARK: - Raw body walk (the structure-free fallback)

    /// A body cut off before the closing "--XyZ--" keeps its last part.
    func testTruncatedMultipartKeepsLastPart() {
        let body = "--XyZ\r\nContent-Type: text/plain; charset=\"utf-8\"\r\n\r\nfirst\r\n"
            + "--XyZ\r\nContent-Type: text/plain; charset=\"utf-8\"\r\n\r\nsecond, truncated"
        let parts = MIMEDecode.splitParts(Data(body.utf8), boundary: "XyZ")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(String(decoding: parts[1], as: UTF8.self), "Content-Type: text/plain; charset=\"utf-8\"\r\n\r\nsecond, truncated")
        // Even a single opening delimiter with nothing after it yields that part.
        let single = MIMEDecode.splitParts(Data("--XyZ\r\nContent-Type: text/plain\r\n\r\nonly".utf8), boundary: "XyZ")
        XCTAssertEqual(single.count, 1)
        XCTAssertEqual(
            MIMEDecode.extractText(rawBody: Data(body.utf8), contentType: "multipart/mixed; boundary=XyZ", transferEncoding: "7bit"),
            "first"
        )
    }

    /// Boundary "abc" must not match the nested "--abcd" lines, and a
    /// delimiter only counts at the start of a line.
    func testPrefixBoundaryDoesNotMatchLongerNestedBoundary() {
        let inner = "--abcd\r\nContent-Type: text/plain; charset=\"utf-8\"\r\n\r\ninner text\r\n--abcd--\r\n"
        let outer = "--abc\r\nContent-Type: multipart/alternative; boundary=\"abcd\"\r\n\r\n\(inner)\r\n--abc--\r\n"
        let outerParts = MIMEDecode.splitParts(Data(outer.utf8), boundary: "abc")
        XCTAssertEqual(outerParts.count, 1)
        XCTAssertEqual(MIMEDecode.splitParts(outerParts[0], boundary: "abcd").count, 1)
        XCTAssertEqual(
            MIMEDecode.extractText(rawBody: Data(outer.utf8), contentType: "multipart/mixed; boundary=abc", transferEncoding: "7bit"),
            "inner text"
        )
        // "--abc" in the middle of a line is body text, not a delimiter.
        let midLine = "--abc\r\n\r\nsee --abc here\r\n--abc--\r\n"
        let midParts = MIMEDecode.splitParts(Data(midLine.utf8), boundary: "abc")
        XCTAssertEqual(midParts.map { String(decoding: $0, as: UTF8.self) }, ["\r\nsee --abc here"])
    }

    /// HTML wins in the fallback walk too — same reasoning as
    /// IMAPParser.findTextPart.
    func testMultipartWalkPrefersHTML() {
        let plain = Data("плохой авто-текст".utf8).base64EncodedString()
        let body = "--XyZ\r\nContent-Type: text/plain; charset=\"utf-8\"\r\nContent-Transfer-Encoding: base64\r\n\r\n\(plain)\r\n"
            + "--XyZ\r\nContent-Type: text/html; charset=\"utf-8\"\r\n\r\n<p>Привет из письма</p>\r\n--XyZ--\r\n"
        let readable = MIMEDecode.extractReadable(
            rawBody: Data(body.utf8),
            contentType: "multipart/alternative; boundary=\"XyZ\"",
            transferEncoding: "7bit"
        )
        XCTAssertEqual(readable.text, "Привет из письма")
        XCTAssertNotNil(readable.html, "the reader needs the HTML source to render richly")
    }

    /// Plain-only mail keeps working.
    func testMultipartWalkFallsBackToPlain() {
        let plain = Data("только текст".utf8).base64EncodedString()
        let body = "--XyZ\r\nContent-Type: text/plain; charset=\"utf-8\"\r\nContent-Transfer-Encoding: base64\r\n\r\n\(plain)\r\n--XyZ--\r\n"
        let readable = MIMEDecode.extractReadable(
            rawBody: Data(body.utf8),
            contentType: "multipart/alternative; boundary=\"XyZ\"",
            transferEncoding: "7bit"
        )
        XCTAssertEqual(readable.text, "только текст")
        XCTAssertNil(readable.html)
    }

    func testHTMLOnlyBodyIsFlattened() {
        let html = Data("<html><body><p>Привет</p><p>мир</p></body></html>".utf8).base64EncodedString()
        XCTAssertEqual(
            MIMEDecode.extractText(rawBody: Data(html.utf8), contentType: "text/html; charset=utf-8", transferEncoding: "base64"),
            "Привет\nмир"
        )
    }

    func testAttachmentOnlyBodyYieldsNothing() {
        XCTAssertEqual(
            MIMEDecode.extractText(rawBody: Data("%PDF-1.4".utf8), contentType: "application/pdf", transferEncoding: "base64"),
            ""
        )
    }

    func testHTMLStripping() {
        let html = "<style>a{color:red}</style><p>Hi&nbsp;there</p><br><div>&#1055;&#1088;&#1080;</div>"
        XCTAssertEqual(MIMEDecode.htmlToPlainText(html), "Hi\u{00A0}there\n\nПри")
    }

    /// A bare "<" in prose is text, not a tag opener that eats up to the next ">".
    func testBareLessThanInProseSurvives() {
        XCTAssertEqual(MIMEDecode.htmlToPlainText("<p>a < b</p>"), "a < b")
        XCTAssertEqual(MIMEDecode.htmlToPlainText("<p>1 < 2 and 3 > 2</p><p>next</p>"), "1 < 2 and 3 > 2\nnext")
        XCTAssertEqual(MIMEDecode.htmlToPlainText("x <!-- hidden --> y <?xml?> z"), "x  y  z")
        // "<head" must not swallow "<header>…</header>".
        XCTAssertEqual(
            MIMEDecode.htmlToPlainText("<head><title>T</title></head><header>Nav</header> <p>Body</p>"),
            "Nav Body"
        )
    }

    // MARK: - Dates

    func testDates() {
        let rfc = MIMEDecode.parseDate("Mon, 25 Aug 2026 13:30:04 +0300")
        XCTAssertEqual(rfc?.timeIntervalSince1970, 1_787_653_804)
        XCTAssertEqual(MIMEDecode.parseDate("25-Aug-2026 10:30:04 +0000"), rfc)
        XCTAssertEqual(MIMEDecode.parseDate("Mon, 25 Aug 2026 13:30:04 +0300 (MSK)"), rfc)
        XCTAssertNil(MIMEDecode.parseDate("yesterday"))
    }
}
