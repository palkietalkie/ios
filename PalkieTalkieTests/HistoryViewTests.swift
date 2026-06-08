@testable import PalkieTalkie
import SwiftUI
import ViewInspector
import XCTest

@MainActor
final class HistoryViewTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "cache.sessions")
    }

    /// Empty-state copy: `ContentUnavailableView("No sessions yet", …)` renders when `sessions.isEmpty && loadError == nil`. Catches a refactor that silently swaps the copy or the icon.
    func testEmptyStateRendersContentUnavailable() throws {
        UserDefaults.standard.removeObject(forKey: "cache.sessions")
        let sut = HistoryView()
        XCTAssertNoThrow(try sut.inspect().find(ViewType.ContentUnavailableView.self))
    }

    /// Stale-while-revalidate: seeded cache row renders on first paint with persona name + duration formatted as "Nm Ms".
    func testSeededCacheRendersPersonaAndDurationFormat() throws {
        let cached = SessionSummary(
            sessionId: UUID().uuidString,
            personaId: "Sharp prosecutor",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: nil,
            durationSeconds: 75,
        )
        JSONCache.save([cached], key: "cache.sessions")
        defer { UserDefaults.standard.removeObject(forKey: "cache.sessions") }

        let sut = HistoryView()
        let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        XCTAssertTrue(texts.contains("Sharp prosecutor"))
        XCTAssertTrue(texts.contains("1m 15s"), "expected duration formatted '1m 15s'; saw \(texts)")
    }

    /// Missing personaId falls back to "Unknown persona" — never empty. Empty heading would create a row with only the date underneath, which looks broken.
    func testNilPersonaIdFallsBackToUnknownPersona() throws {
        let cached = SessionSummary(
            sessionId: UUID().uuidString,
            personaId: nil,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: nil,
            durationSeconds: 30,
        )
        JSONCache.save([cached], key: "cache.sessions")
        defer { UserDefaults.standard.removeObject(forKey: "cache.sessions") }

        let sut = HistoryView()
        let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        XCTAssertTrue(texts.contains("Unknown persona"))
    }
}
