import XCTest

final class EmailHTMLTests: XCTestCase {
    // MARK: - HTML sniffing (senders mislabel text/plain constantly)

    func testDetectsObviousHTML() {
        XCTAssertTrue(MIMEDecode.looksLikeHTML("<!DOCTYPE html><html><body>hi</body></html>"))
        XCTAssertTrue(MIMEDecode.looksLikeHTML("<html dir=\"ltr\"><p>Привет</p>"))
        // No <html> wrapper, but clearly markup: several structural tags.
        XCTAssertTrue(MIMEDecode.looksLikeHTML("<div style=\"x\"><table><td>cell</td></table></div>"))
    }

    func testPlainProseIsNotHTML() {
        XCTAssertFalse(MIMEDecode.looksLikeHTML("Привет! Встречаемся в 15:00."))
        // One tag quoted in prose must not flip the whole message to HTML.
        XCTAssertFalse(MIMEDecode.looksLikeHTML("используй тег <br> для переноса"))
        XCTAssertFalse(MIMEDecode.looksLikeHTML("a < b и b > c — это математика"))
    }

    func testExtractReadableCarriesHTMLSource() {
        let html = "<html><body><p>Привет <b>мир</b></p></body></html>"
        let readable = MIMEDecode.extractReadable(
            rawBody: Data(html.utf8),
            contentType: "text/html; charset=utf-8",
            transferEncoding: "7bit"
        )
        XCTAssertEqual(readable.html, html, "the reader needs the source, not just flattened text")
        XCTAssertTrue(readable.text.contains("Привет"))
        XCTAssertFalse(readable.text.contains("<b>"))
    }

    func testExtractReadablePlainHasNoHTML() {
        let readable = MIMEDecode.extractReadable(
            rawBody: Data("просто текст".utf8),
            contentType: "text/plain; charset=utf-8",
            transferEncoding: "7bit"
        )
        XCTAssertNil(readable.html)
        XCTAssertEqual(readable.text, "просто текст")
    }

    // MARK: - Pre-render stripping (privacy: no remote loads, ever)

    func testStripsScriptsStylesAndHead() {
        let html = """
        <html><head><style>body{color:#000}</style></head><body>
        <img src="https://tracker.example/pixel.gif" width="1" height="1">
        <p>Текст письма</p>
        <script>alert(1)</script>
        <IMG SRC="https://cdn.example/banner.png">
        </body></html>
        """
        let cleaned = EmailHTMLSanitizer.strip(html)
        // Images stay in the DOM — the reader hides them with CSS and blocks
        // their loads, so the show-images button can reveal them later.
        XCTAssertTrue(cleaned.lowercased().contains("<img"))
        XCTAssertFalse(cleaned.contains("<script"))
        XCTAssertFalse(cleaned.contains("<head"))
        XCTAssertFalse(cleaned.lowercased().contains("<style"), "sender CSS wars with the reader restyle")
        XCTAssertTrue(cleaned.contains("Текст письма"))
    }
}
