@testable import PalkieTalkie
import SwiftUI
import XCTest

/// MetricInfo statics + the MetricExplainerSheet body. The bigger StatsView coverage comes from ViewBodyTests rendering the body; here we cover the per-metric definitions individually.
@MainActor
final class StatsViewHelpersTests: XCTestCase {
    func testAllMetricInfosHaveIdentifiers() {
        let metrics: [MetricInfo] = [
            .minutes, .sessions, .uniqueWords, .uniquePhrases,
            .talkShare, .speakingRate, .pitchRange, .cefr,
        ]
        // Each one should self-identify and carry text the UI uses.
        let ids = metrics.map(\.id)
        XCTAssertEqual(Set(ids).count, metrics.count, "every metric needs a unique id")
        for m in metrics {
            XCTAssertFalse(m.id.isEmpty)
            XCTAssertFalse(m.title.isEmpty)
            XCTAssertFalse(m.explanation.isEmpty)
        }
    }

    func testMetricsHaveExpectedSlugs() {
        XCTAssertEqual(MetricInfo.minutes.id, "minutes")
        XCTAssertEqual(MetricInfo.sessions.id, "sessions")
        XCTAssertEqual(MetricInfo.uniqueWords.id, "uniqueWords")
        XCTAssertEqual(MetricInfo.uniquePhrases.id, "uniquePhrases")
        XCTAssertEqual(MetricInfo.talkShare.id, "talkShare")
        XCTAssertEqual(MetricInfo.speakingRate.id, "speakingRate")
        XCTAssertEqual(MetricInfo.pitchRange.id, "pitchRange")
        XCTAssertEqual(MetricInfo.cefr.id, "cefr")
    }

    func testMetricComputationsReadInPlainLanguage() {
        let metrics: [MetricInfo] = [
            .minutes, .sessions, .uniqueWords, .uniquePhrases,
            .talkShare, .speakingRate, .pitchRange, .cefr,
        ]
        // `computation` is shown to the user, so it must never leak implementation terms (DB tables, "NLP pipeline", lemmatization) — the phrasing the plain-language pass replaced.
        let internalTerms = ["conversation_sessions", "transcript", "NLP", "lemmati", "pipeline"]
        for m in metrics {
            guard let computation = m.computation else { continue }
            for term in internalTerms {
                XCTAssertFalse(
                    computation.localizedCaseInsensitiveContains(term),
                    "\(m.id) computation leaks internal term '\(term)': \(computation)",
                )
            }
        }
    }

    func testMetricExplainerSheetBodyForEveryMetric() {
        for info in [
            MetricInfo.minutes,
            .sessions,
            .uniqueWords,
            .uniquePhrases,
            .talkShare,
            .speakingRate,
            .pitchRange,
            .cefr,
        ] {
            let view = MetricExplainerSheet(info: info)
            _ = view.body
        }
    }

    /// Hosts StatsView with a canned backend response so each metricCard, cefrCard ForEach, and formatter branch (with non-nil values) runs.
    func testHostsStatsViewWithLoadedData() async throws {
        let transport = FakeTransport()
        let stats = Stats(
            dayStreak: 7,
            sessionTotalSeconds: 360,
            sessionsCount: 4,
            uniqueWords: 250,
            uniquePhrases: 30,
            userTalkPct: 0.55,
            speakingRateWpm: 142,
            pitchMinHz: 90,
            pitchMaxHz: 230,
            affinity: 5,
            cefrCoverage: [
                CEFRCoverage(level: "A1", totalWords: 500, usedWords: 400, coveragePct: 0.8),
                CEFRCoverage(level: "B1", totalWords: 1000, usedWords: 300, coveragePct: 0.3),
            ],
        )
        transport.responseData = try BackendAPI.encoder.encode(stats)
        let api = try BackendAPI(
            baseURL: XCTUnwrap(URL(string: "https://test.example.com")),
            transport: transport,
            auth: StubAuthing(),
        )
        await TestHosting.host(StatsView().environment(\.backendAPI, api), settleMs: 500)
    }

    /// Streak = 1 → "day in a row" (singular). Covers the ternary branch in hero().
    func testHostsStatsViewWithStreakOfOne() async throws {
        let transport = FakeTransport()
        let stats = Stats(
            dayStreak: 1, sessionTotalSeconds: 60, sessionsCount: 1,
            uniqueWords: 10, uniquePhrases: 1,
            userTalkPct: nil, speakingRateWpm: nil, pitchMinHz: nil, pitchMaxHz: nil,
            affinity: 0,
            cefrCoverage: [],
        )
        transport.responseData = try BackendAPI.encoder.encode(stats)
        let api = try BackendAPI(
            baseURL: XCTUnwrap(URL(string: "https://test.example.com")),
            transport: transport,
            auth: StubAuthing(),
        )
        await TestHosting.host(StatsView().environment(\.backendAPI, api), settleMs: 400)
    }

    /// Load fails — covers the catch branch that sets loadError + the Text view rendering it.
    func testHostsStatsViewWithLoadErrorSurfacesMessage() async throws {
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = Data("boom".utf8)
        let api = try BackendAPI(
            baseURL: XCTUnwrap(URL(string: "https://test.example.com")),
            transport: transport,
            auth: StubAuthing(),
        )
        await TestHosting.host(StatsView().environment(\.backendAPI, api), settleMs: 400)
    }
}
