@testable import PalkieTalkie
import XCTest

@MainActor
final class FreeCapLimitViewTests: XCTestCase {
    /// The spoken announcement must match which cap was hit (today vs this week), the same split as the on-screen title.
    func testSpokenLineMatchesCapKind() {
        let daily = FreeCapLimitView.spokenLine(isWeekly: false)
        let weekly = FreeCapLimitView.spokenLine(isWeekly: true)
        XCTAssertNotEqual(daily, weekly)
        XCTAssertTrue(daily.lowercased().contains("today"), daily)
        XCTAssertTrue(weekly.lowercased().contains("week"), weekly)
    }

    /// The local notification's text matches the cap, and "back Monday" wording only appears for the weekly block.
    func testNotificationTextMatchesCapKind() {
        let daily = freeCapNotificationText(isWeekly: false)
        let weekly = freeCapNotificationText(isWeekly: true)
        XCTAssertTrue(daily.title.lowercased().contains("today"), daily.title)
        XCTAssertTrue(daily.body.lowercased().contains("tomorrow"), daily.body)
        XCTAssertTrue(weekly.title.lowercased().contains("week"), weekly.title)
        XCTAssertTrue(weekly.body.lowercased().contains("monday"), weekly.body)
    }
}
