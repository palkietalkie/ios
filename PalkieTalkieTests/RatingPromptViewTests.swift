import Foundation
@testable import PalkieTalkie
import XCTest

/// Rating-prompt timing + routing: ask only after enough cumulative conversation (minutes, not session count), then re-ask on a fixed cadence so we use up to Apple's 3 prompts per rolling 365 days, and send happy users to the App Store while keeping unhappy feedback private.
final class RatingPromptViewTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var secondsPerDay: Double {
        24 * 60 * 60
    }

    func testDoesNotAskBelowEngagementThreshold() {
        XCTAssertFalse(RatingPolicy.shouldPrompt(totalMinutes: 59, lastPromptedAt: nil, now: now))
    }

    func testAsksWhenEngagedAndNeverAsked() {
        XCTAssertTrue(RatingPolicy.shouldPrompt(totalMinutes: 60, lastPromptedAt: nil, now: now))
        XCTAssertTrue(RatingPolicy.shouldPrompt(totalMinutes: 500, lastPromptedAt: nil, now: now))
    }

    func testDoesNotReAskWithinTheInterval() {
        let lastAsked = now.addingTimeInterval(-Double(RatingPolicy.reAskAfterDays - 1) * secondsPerDay)
        XCTAssertFalse(RatingPolicy.shouldPrompt(totalMinutes: 500, lastPromptedAt: lastAsked, now: now))
    }

    func testReAsksAfterTheInterval() {
        let lastAsked = now.addingTimeInterval(-Double(RatingPolicy.reAskAfterDays) * secondsPerDay)
        XCTAssertTrue(RatingPolicy.shouldPrompt(totalMinutes: 500, lastPromptedAt: lastAsked, now: now))
    }

    func testHighRatingsRouteToAppStoreLowOnesStayPrivate() {
        XCTAssertTrue(RatingPolicy.routesToAppStore(rating: 5))
        XCTAssertTrue(RatingPolicy.routesToAppStore(rating: 4))
        XCTAssertFalse(RatingPolicy.routesToAppStore(rating: 3))
        XCTAssertFalse(RatingPolicy.routesToAppStore(rating: 1))
    }
}
