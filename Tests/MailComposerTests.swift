import XCTest

final class MailComposerTests: XCTestCase {
    private let reply = OutgoingMail(
        from: "me@example.com",
        to: "them@example.com",
        subject: "Re: Привет",
        body: "Привет!\nЭто ответ из виджета.\n\n.точка в начале строки",
        inReplyTo: "<parent@acme.io>",
        references: ["<root@acme.io>"]
    )

    private func compose(_ mail: OutgoingMail) -> String {
        MailComposer.rfc5322(mail, messageID: "<fixed@hotzisland>", date: Date(timeIntervalSince1970: 1_787_653_804))
    }

    private func headerBlock(_ message: String) -> [String: String] {
        MIMEDecode.parseHeaders(Data(message.utf8))
    }

    func testThreadingHeaders() {
        let headers = headerBlock(compose(reply))
        XCTAssertEqual(headers["in-reply-to"], "<parent@acme.io>")
        // The parent joins the chain it inherited, in order.
        XCTAssertEqual(headers["references"], "<root@acme.io> <parent@acme.io>")
        XCTAssertEqual(headers["message-id"], "<fixed@hotzisland>")
        XCTAssertEqual(headers["content-transfer-encoding"], "base64")
    }

    func testParentIsNotRepeatedWhenAlreadyInTheChain() {
        var mail = reply
        mail.references = ["<root@acme.io>", "<parent@acme.io>"]
        XCTAssertEqual(headerBlock(compose(mail))["references"], "<root@acme.io> <parent@acme.io>")
    }

    func testBodyRoundTripsThroughBase64() throws {
        let message = compose(reply)
        let (_, body) = MIMEDecode.splitHeaderAndBody(Data(message.utf8))
        let decoded = try XCTUnwrap(Data(base64Encoded: body, options: .ignoreUnknownCharacters))
        XCTAssertEqual(String(decoding: decoded, as: UTF8.self), reply.body)
    }

    func testEveryLineStaysWithinTheRFCLimit() {
        // 998 is the hard limit; base64 wrapping and header folding keep us
        // far below it, and a line starting with "." would need dot-stuffing.
        for line in compose(reply).components(separatedBy: "\r\n") {
            XCTAssertLessThanOrEqual(line.count, 998)
            XCTAssertFalse(line.hasPrefix("."), "a bare dot line would end DATA early")
        }
    }

    func testSubjectEncodingAndDecodingRoundTrip() {
        let subject = "Привет, это довольно длинная тема письма, которая не влезает в одно encoded-word"
        let encoded = MailComposer.encodeHeader(subject)
        for line in encoded.components(separatedBy: "\r\n") {
            XCTAssertLessThanOrEqual(line.trimmingCharacters(in: .whitespaces).count, 75)
        }
        // Folding whitespace between encoded words disappears on decode.
        XCTAssertEqual(MIMEDecode.decodeEncodedWords(encoded.replacingOccurrences(of: "\r\n", with: "")), subject)
    }

    func testAsciiSubjectIsLeftAlone() {
        XCTAssertEqual(MailComposer.encodeHeader("Plain subject"), "Plain subject")
    }

    func testReplySubjectPrefixesOnce() {
        XCTAssertEqual(MailComposer.replySubject("Привет"), "Re: Привет")
        XCTAssertEqual(MailComposer.replySubject("Re: Привет"), "Re: Привет")
        XCTAssertEqual(MailComposer.replySubject("RE: Привет"), "RE: Привет")
        XCTAssertEqual(MailComposer.replySubject(""), "Re:")
    }

    func testDateFormatParsesBack() {
        let date = Date(timeIntervalSince1970: 1_787_653_804)
        XCTAssertEqual(MIMEDecode.parseDate(MailComposer.rfc5322Date(date)), date)
    }
}
