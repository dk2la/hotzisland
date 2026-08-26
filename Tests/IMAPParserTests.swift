import XCTest

/// Fixtures shaped like real Gmail/Yandex FETCH responses. The regression
/// that motivated them: a `NIL` inside ENVELOPE used to end the enclosing
/// list, so subjects vanished and bodies rendered as raw base64.
final class IMAPParserTests: XCTestCase {
    // multipart/alternative, everything quoted — the everyday Gmail shape.
    private let alternative = """
    * 5 FETCH (UID 12345 FLAGS (\\Seen) INTERNALDATE "25-Aug-2026 10:30:04 +0000" \
    ENVELOPE ("Mon, 25 Aug 2026 13:30:04 +0300" "=?UTF-8?B?0J/RgNC40LLQtdGC?=" \
    (("Google" NIL "no-reply" "accounts.google.com")) (("Google" NIL "no-reply" "accounts.google.com")) \
    (("Google" NIL "no-reply" "accounts.google.com")) ((NIL NIL "d.kzlv2la" "gmail.com")) \
    NIL NIL NIL "<abc123@mail.gmail.com>") \
    BODYSTRUCTURE (("TEXT" "PLAIN" ("CHARSET" "UTF-8") NIL NIL "BASE64" 1234 20 NIL NIL NIL NIL)\
    ("TEXT" "HTML" ("CHARSET" "UTF-8") NIL NIL "QUOTED-PRINTABLE" 5678 90 NIL NIL NIL NIL) \
    "ALTERNATIVE" ("BOUNDARY" "0000000000") NIL NIL NIL))\r\n
    """

    func testEnvelopeSurvivesNILFields() throws {
        let item = try XCTUnwrap(IMAPParser.parseFetch(Data(alternative.utf8)))
        let envelope = try XCTUnwrap(item.envelope, "NIL must not truncate the envelope list")
        XCTAssertEqual(item.uid, 12345)
        XCTAssertEqual(item.flags, ["\\Seen"])
        XCTAssertEqual(envelope.subject, "Привет")
        XCTAssertEqual(envelope.fromName, "Google")
        XCTAssertEqual(envelope.fromAddress, "no-reply@accounts.google.com")
        XCTAssertEqual(envelope.messageID, "<abc123@mail.gmail.com>")
    }

    func testPrefersPlainTextPart() throws {
        let item = try XCTUnwrap(IMAPParser.parseFetch(Data(alternative.utf8)))
        let part = try XCTUnwrap(item.textPart)
        XCTAssertEqual(part.section, "1")
        XCTAssertEqual(part.encoding, "BASE64")
        XCTAssertEqual(part.charset, "UTF-8")
        XCTAssertFalse(part.isHTML)
    }

    func testLiteralSubjectAndSinglePartBody() throws {
        let subject = "=?UTF-8?B?0J/RgNC40LLQtdGCLCDQvNC40YA=?="
        let unit = "* 6 FETCH (UID 12346 FLAGS () INTERNALDATE \"25-Aug-2026 09:05:00 +0000\" "
            + "ENVELOPE (\"Mon, 25 Aug 2026 12:05:00 +0300\" {\(subject.utf8.count)}\r\n\(subject) "
            + "((\"Yandex\" NIL \"noreply\" \"yandex.ru\")) ((\"Yandex\" NIL \"noreply\" \"yandex.ru\")) "
            + "((\"Yandex\" NIL \"noreply\" \"yandex.ru\")) ((NIL NIL \"d.kzlv2la\" \"gmail.com\")) "
            + "NIL NIL NIL \"<xyz@yandex.ru>\") "
            + "BODYSTRUCTURE (\"TEXT\" \"PLAIN\" (\"CHARSET\" \"KOI8-R\") NIL NIL \"8BIT\" 400 10 NIL NIL NIL NIL))\r\n"
        let item = try XCTUnwrap(IMAPParser.parseFetch(Data(unit.utf8)))
        XCTAssertEqual(item.envelope?.subject, "Привет, мир")
        XCTAssertEqual(item.textPart?.section, "1")
        XCTAssertEqual(item.textPart?.charset, "KOI8-R")
    }

    func testNestedMultipartSectionPath() throws {
        let unit = "* 7 FETCH (UID 12347 FLAGS (\\Seen) INTERNALDATE \"24-Aug-2026 22:00:00 +0000\" "
            + "ENVELOPE (\"Sun, 24 Aug 2026 22:00:00 +0000\" \"Invoice\" "
            + "((\"Acme\" NIL \"billing\" \"acme.io\")) ((\"Acme\" NIL \"billing\" \"acme.io\")) "
            + "((\"Acme\" NIL \"billing\" \"acme.io\")) ((NIL NIL \"d.kzlv2la\" \"gmail.com\")) "
            + "NIL NIL \"<parent@acme.io>\" \"<child@acme.io>\") "
            + "BODYSTRUCTURE (((\"TEXT\" \"PLAIN\" (\"CHARSET\" \"UTF-8\") NIL NIL \"QUOTED-PRINTABLE\" 700 12 NIL NIL NIL NIL)"
            + "(\"TEXT\" \"HTML\" (\"CHARSET\" \"UTF-8\") NIL NIL \"QUOTED-PRINTABLE\" 2200 40 NIL NIL NIL NIL) "
            + "\"ALTERNATIVE\" (\"BOUNDARY\" \"aaa\") NIL NIL NIL)"
            + "(\"APPLICATION\" \"PDF\" (\"NAME\" \"inv.pdf\") NIL NIL \"BASE64\" 90000 NIL (\"ATTACHMENT\" (\"FILENAME\" \"inv.pdf\")) NIL NIL) "
            + "\"MIXED\" (\"BOUNDARY\" \"bbb\") NIL NIL NIL))\r\n"
        let item = try XCTUnwrap(IMAPParser.parseFetch(Data(unit.utf8)))
        XCTAssertEqual(item.envelope?.inReplyTo, "<parent@acme.io>")
        XCTAssertEqual(item.textPart?.section, "1.1")
    }

    func testFallsBackToHTMLWhenThatIsAllThereIs() throws {
        let unit = "* 8 FETCH (UID 12348 FLAGS () ENVELOPE (\"Mon, 25 Aug 2026 07:34:00 +0300\" \"News\" "
            + "((NIL NIL \"news\" \"substack.com\")) ((NIL NIL \"news\" \"substack.com\")) "
            + "((NIL NIL \"news\" \"substack.com\")) ((NIL NIL \"d.kzlv2la\" \"gmail.com\")) NIL NIL NIL \"<n@substack.com>\") "
            + "BODYSTRUCTURE (\"TEXT\" \"HTML\" (\"CHARSET\" \"windows-1251\") NIL NIL \"BASE64\" 9000 120 NIL NIL NIL NIL))\r\n"
        let item = try XCTUnwrap(IMAPParser.parseFetch(Data(unit.utf8)))
        let part = try XCTUnwrap(item.textPart)
        XCTAssertTrue(part.isHTML)
        XCTAssertEqual(part.charset, "windows-1251")
        // A sender with no display name falls back to the address.
        XCTAssertEqual(item.envelope?.fromName, "news@substack.com")
    }

    func testSkipsTextAttachmentInFavourOfTheBody() throws {
        let unit = "* 9 FETCH (UID 12349 FLAGS () ENVELOPE (\"Mon, 25 Aug 2026 06:33:00 +0300\" \"Log\" "
            + "((NIL NIL \"ci\" \"build.io\")) ((NIL NIL \"ci\" \"build.io\")) ((NIL NIL \"ci\" \"build.io\")) "
            + "((NIL NIL \"d.kzlv2la\" \"gmail.com\")) NIL NIL NIL \"<c@build.io>\") "
            + "BODYSTRUCTURE ((\"TEXT\" \"HTML\" (\"CHARSET\" \"UTF-8\") NIL NIL \"7BIT\" 500 8 NIL NIL NIL NIL)"
            + "(\"TEXT\" \"PLAIN\" (\"NAME\" \"build.log\") NIL NIL \"BASE64\" 40000 900 NIL (\"ATTACHMENT\" (\"FILENAME\" \"build.log\")) NIL NIL) "
            + "\"MIXED\" (\"BOUNDARY\" \"ccc\") NIL NIL NIL))\r\n"
        let part = try XCTUnwrap(IMAPParser.parseFetch(Data(unit.utf8))?.textPart)
        XCTAssertEqual(part.section, "1")
        XCTAssertTrue(part.isHTML, "the attached .log must not win over the body")
    }

    /// "BODY[HEADER.FIELDS (…)]" holds spaces and parens inside its brackets;
    /// tokenizing it as three values would shift every key/value pair.
    func testBracketedSectionKeysStayWhole() throws {
        let headers = "Content-Type: multipart/alternative; boundary=\"XyZ\"\r\nContent-Transfer-Encoding: 7bit\r\n\r\n"
        let unit = "* 10 FETCH (UID 12350 "
            + "BODY[HEADER.FIELDS (CONTENT-TYPE CONTENT-TRANSFER-ENCODING)] {\(headers.utf8.count)}\r\n\(headers) "
            + "BODY[TEXT]<0> {5}\r\nhello)\r\n"
        let item = try XCTUnwrap(IMAPParser.parseFetch(Data(unit.utf8)))
        XCTAssertEqual(item.uid, 12350)
        XCTAssertEqual(item.bodyPayloads["TEXT"], Data("hello".utf8))
        let raw = try XCTUnwrap(item.bodyPayloads.first { $0.key.hasPrefix("HEADER.FIELDS") }?.value)
        XCTAssertEqual(MIMEDecode.parseHeaders(raw)["content-transfer-encoding"], "7bit")
    }

    func testSearchAndExists() {
        XCTAssertEqual(IMAPParser.parseSearch(Data("* SEARCH 4 8 15\r\n".utf8)), [4, 8, 15])
        XCTAssertEqual(IMAPParser.parseExists(Data("* 231 EXISTS\r\n".utf8)), 231)
        XCTAssertNil(IMAPParser.parseSearch(Data("* 231 EXISTS\r\n".utf8)))
    }
}
