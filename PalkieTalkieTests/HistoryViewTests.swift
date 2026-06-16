@testable import PalkieTalkie
import SwiftUI
import ViewInspector
import XCTest

@MainActor
final class HistoryViewTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "cache.sessions")
    }

    override func tearDown() async throws {
        try? await Task.sleep(nanoseconds: 300_000_000)
        UserDefaults.standard.removeObject(forKey: "cache.sessions")
        try await super.tearDown()
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

    /// Hosts HistoryView with canned /conversation/sessions so the load success path runs and the row body renders (covers durationSeconds optional unwrap, date formatting).
    func testHostsWithLoadedSessions() async throws {
        let transport = FakeTransport()
        let sessions = [
            SessionSummary(
                sessionId: "s1",
                personaId: "Coach A",
                startedAt: Date(),
                endedAt: nil,
                durationSeconds: 125,
            ),
            SessionSummary(sessionId: "s2", personaId: nil, startedAt: Date(), endedAt: nil, durationSeconds: nil),
        ]
        transport.responseData = try BackendAPI.encoder.encode(sessions)
        let api = try BackendAPI(
            baseURL: XCTUnwrap(URL(string: "https://test.example.com")),
            transport: transport,
            auth: StubAuthing(),
        )
        await TestHosting.host(HistoryView().environment(\.backendAPI, api), settleMs: 500)
    }

    /// Backend errors on /sessions — covers the catch branch + the alert binding.
    func testHostsWithLoadErrorTriggersAlertBranch() async throws {
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = Data("boom".utf8)
        let api = try BackendAPI(
            baseURL: XCTUnwrap(URL(string: "https://test.example.com")),
            transport: transport,
            auth: StubAuthing(),
        )
        await TestHosting.host(HistoryView().environment(\.backendAPI, api), settleMs: 500)
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

    /// Sub-minute duration formats as "0m Ns" via `Text(verbatim:)` (a pure computed value, kept out of the String Catalog). Pins the minutes-zero case so the verbatim format string can't regress to a bare second count.
    func testSubMinuteDurationFormatsWithZeroMinutes() throws {
        let cached = SessionSummary(
            sessionId: UUID().uuidString,
            personaId: "Coach B",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: nil,
            durationSeconds: 42,
        )
        JSONCache.save([cached], key: "cache.sessions")
        defer { UserDefaults.standard.removeObject(forKey: "cache.sessions") }

        let sut = HistoryView()
        let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        XCTAssertTrue(texts.contains("0m 42s"), "expected '0m 42s'; saw \(texts)")
    }
}
