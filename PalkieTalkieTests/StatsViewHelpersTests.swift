@testable import PalkieTalkie
import SwiftUI
import XCTest

/// MetricInfo statics + the MetricExplainerSheet body. The bigger StatsView coverage comes from ViewBodyTests rendering
/// the body; here we cover the per-metric definitions individually.
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
}
