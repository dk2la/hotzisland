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

    // MARK: - Raw body walk (the structure-free fallback)

    func testMultipartWalkPrefersPlainText() {
        let plain = Data("Привет из письма".utf8).base64EncodedString()
        let body = "--XyZ\r\nContent-Type: text/plain; charset=\"utf-8\"\r\nContent-Transfer-Encoding: base64\r\n\r\n\(plain)\r\n"
            + "--XyZ\r\nContent-Type: text/html; charset=\"utf-8\"\r\n\r\n<p>ignored</p>\r\n--XyZ--\r\n"
        XCTAssertEqual(
            MIMEDecode.extractText(
                rawBody: Data(body.utf8),
                contentType: "multipart/alternative; boundary=\"XyZ\"",
                transferEncoding: "7bit"
            ),
            "Привет из письма"
        )
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

    // MARK: - Dates

    func testDates() {
        let rfc = MIMEDecode.parseDate("Mon, 25 Aug 2026 13:30:04 +0300")
        XCTAssertEqual(rfc?.timeIntervalSince1970, 1_787_653_804)
        XCTAssertEqual(MIMEDecode.parseDate("25-Aug-2026 10:30:04 +0000"), rfc)
        XCTAssertEqual(MIMEDecode.parseDate("Mon, 25 Aug 2026 13:30:04 +0300 (MSK)"), rfc)
        XCTAssertNil(MIMEDecode.parseDate("yesterday"))
    }
}
