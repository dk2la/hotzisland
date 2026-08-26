import XCTest

/// The on-device recognizer resets its transcription after a pause with no
/// event at all — the signals are the shape of the next partial and the gap
/// in the partial stream. These pin down the boundary between "reset" and a
/// normal mid-utterance revision.
@MainActor
final class SpeechResetHeuristicTests: XCTestCase {
    /// Steady partial flow — the revision regime.
    private func flowing(_ previous: String, _ incoming: String) -> Bool {
        SpeechCaptureService.looksLikeReset(previous: previous, incoming: incoming, gapSinceLastPartial: 0.2)
    }

    /// Partial arrived after a break in the stream — the pause regime.
    private func afterGap(_ previous: String, _ incoming: String) -> Bool {
        SpeechCaptureService.looksLikeReset(previous: previous, incoming: incoming, gapSinceLastPartial: 1.2)
    }

    func testFreshUtteranceAfterPauseIsAReset() {
        XCTAssertTrue(flowing("это довольно длинное предложение про виджет", "теперь"))
        XCTAssertTrue(flowing("please set a timer for twenty five minutes", "and"))
    }

    /// The field bug: "hello", a short pause, then a LONGER second sentence.
    /// Word counts cannot catch it — the gap in the partial stream does.
    func testLongerUtteranceAfterGapIsAReset() {
        XCTAssertTrue(afterGap("hello", "how are you today"))
        XCTAssertTrue(afterGap("поставь таймер", "запиши заметку купить молоко"))
    }

    func testContinuationAfterGapIsNotAReset() {
        // The recognizer kept the utterance alive across the pause — the new
        // partial extends the old text, so nothing must fold.
        XCTAssertFalse(afterGap("hello", "hello world"))
        XCTAssertFalse(afterGap("привет как", "привет как дела"))
    }

    func testGrowthIsNotAReset() {
        XCTAssertFalse(flowing("привет", "привет как дела"))
        XCTAssertFalse(flowing("set a", "set a timer"))
    }

    func testRevisionsAreNotResets() {
        // Recognizer rewrites words but keeps the head of the utterance.
        XCTAssertFalse(flowing("он пошел в магазин и", "он пошёл в магазин"))
        XCTAssertFalse(flowing("ok so we need", "OK, so we"))
        // Punctuation/case pass over the same words.
        XCTAssertFalse(flowing("привет как дела", "Привет, как дела?"))
    }

    func testShortWholeWordRewriteInFlowIsNotAReset() {
        // Early one-word rewrites are routine ("no" → "know") while partials
        // stream continuously — folding here would duplicate syllables.
        XCTAssertFalse(flowing("no", "know"))
        XCTAssertFalse(flowing("а", "Zach"))
    }

    func testUnrelatedShorterTextIsAResetEvenInFlow() {
        XCTAssertTrue(flowing("поставь таймер", "ага"))
    }
}
