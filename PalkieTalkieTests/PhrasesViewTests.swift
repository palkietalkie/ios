@testable import PalkieTalkie
import SwiftUI
import ViewInspector
import XCTest

@MainActor
final class PhrasesViewTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "cache.phrases")
    }

    /// Stale-while-revalidate: pre-seeded cache renders on first paint so the user sees something instantly instead of an empty list. A refactor that bypasses the cache would silently regress to a network-blocking first paint. Pin the contract by seeding cache and asserting the seeded phrase renders.
    func testRendersSeededCacheOnFirstPaint() throws {
        let cached = PhraseUsage(
            id: "p_1",
            phrase: "kind of",
            count: 7,
            alternatives: ["sort of", "a bit"],
        )
        JSONCache.save([cached], key: "cache.phrases")
        defer { UserDefaults.standard.removeObject(forKey: "cache.phrases") }

        let sut = PhrasesView()
        let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        XCTAssertTrue(texts.contains("kind of"))
        XCTAssertTrue(texts.contains("Used 7×"))
    }

    /// Alternatives render as "Try: a, b" (comma + space separator). A formatting drift would render "Try: a,b" or "Try: a/b" which the marketing+content team has explicitly NOT signed off on.
    func testAlternativesRenderAsCommaSeparatedTryList() throws {
        let cached = PhraseUsage(
            id: "p_1",
            phrase: "kind of",
            count: 7,
            alternatives: ["sort of", "a bit"],
        )
        JSONCache.save([cached], key: "cache.phrases")
        defer { UserDefaults.standard.removeObject(forKey: "cache.phrases") }
        let sut = PhrasesView()
        let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        XCTAssertTrue(texts.contains("Try: sort of, a bit"), "actual: \(texts)")
    }

    /// When alternatives is empty, the "Try:" line MUST NOT render. Otherwise the user sees "Try: " with nothing after it — a UI bug we deliberately guard against with the `if !phrase.alternatives.isEmpty` branch.
    func testNoTryLineWhenAlternativesEmpty() throws {
        let cached = PhraseUsage(id: "p_2", phrase: "literally", count: 2, alternatives: [])
        JSONCache.save([cached], key: "cache.phrases")
        defer { UserDefaults.standard.removeObject(forKey: "cache.phrases") }
        let sut = PhrasesView()
        let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        XCTAssertFalse(texts.contains { $0.hasPrefix("Try:") }, "actual: \(texts)")
    }
}
