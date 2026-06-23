@testable import PalkieTalkie
import XCTest

final class RomanizeTests: XCTestCase {
    private func isLatinOnly(_ s: String) -> Bool {
        s.unicodeScalars
            .allSatisfy {
                $0
                    .isASCII || $0 == "\u{0101}" || $0 == "\u{014D}" || $0 == "\u{016B}" || $0 == "\u{012B}" || $0 ==
                    "\u{0113}"
            }
    }

    /// Kana romanizes to its deterministic reading. Note は as a topic particle transliterates literally to "ha" (kana value), not the phonetic "wa" — the system transcribes script, not pronunciation rules — so the greeting reads "kon'nichiha". Acceptable for a reading aid.
    func testHiraganaGreeting() {
        XCTAssertTrue(romanize("こんにちは").lowercased().contains("nichiha"))
    }

    /// Kansai-dialect speech (the dialect Hashibul picked) transliterates fine — it's just text, so 大阪弁やで becomes readable romaji.
    func testKansaiDialect() {
        let out = romanize("大阪弁やで").lowercased()
        XCTAssertTrue(out.contains("oosaka"), out)
        let hasCJK = out.unicodeScalars.contains { (0x3040 ... 0x9FFF).contains($0.value) }
        XCTAssertFalse(hasCJK, out)
    }

    /// The whole point: kanji must be transcribed via the system dictionary, not left as CJK glyphs. Asserting the output carries no CJK characters proves the readings were resolved (a per-character or no-op transform would leave kanji behind).
    func testKanjiSentenceHasNoRemainingCJK() {
        let out = romanize("今日は晴れです")
        XCTAssertFalse(out.isEmpty)
        let hasCJK = out.unicodeScalars.contains { (0x3040 ... 0x9FFF).contains($0.value) }
        XCTAssertFalse(hasCJK, "kanji/kana should be gone after transcription, got: \(out)")
        XCTAssertTrue(isLatinOnly(out), "transcription should be Latin (with macrons), got: \(out)")
    }

    /// Chinese transcribes to pinyin (same API, different script) — proves it's not Japanese-specific.
    func testChineseProducesLatin() {
        let out = romanize("你好")
        let hasCJK = out.unicodeScalars.contains { (0x3040 ... 0x9FFF).contains($0.value) }
        XCTAssertFalse(hasCJK, "hanzi should be transcribed, got: \(out)")
    }

    /// Already-Latin input (a Spanish-learner's captions) has nothing to transliterate and survives recognizably.
    func testLatinScriptPassesThrough() {
        XCTAssertTrue(romanize("Buenos días").lowercased().contains("buenos"))
    }

    func testEmptyStringIsUnchanged() {
        XCTAssertEqual(romanize(""), "")
    }

    /// The gate for whether the ABC toggle appears at all. English (and any Latin-script target — the primary ICP learning English) has nothing to romanize, so it returns false and the control stays hidden.
    func testHasNonLatinScriptFalseForLatin() {
        XCTAssertFalse(hasNonLatinScript("Hello, how are you today?"))
        XCTAssertFalse(hasNonLatinScript("Buenos días, ¿qué tal?"))
    }

    /// Non-Latin targets (the romaji/pinyin direction) return true so the toggle is offered; a single non-Latin character in otherwise-Latin text is enough.
    func testHasNonLatinScriptTrueForNonLatin() {
        XCTAssertTrue(hasNonLatinScript("今日はいい天気ですね"))
        XCTAssertTrue(hasNonLatinScript("你好"))
        XCTAssertTrue(hasNonLatinScript("안녕하세요"))
        XCTAssertTrue(hasNonLatinScript("namaste नमस्ते"))
        XCTAssertTrue(hasNonLatinScript("the word is 日本"))
    }
}
