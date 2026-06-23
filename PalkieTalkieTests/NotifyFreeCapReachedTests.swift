@testable import PalkieTalkie
import XCTest

@MainActor
final class NotifyFreeCapReachedTests: XCTestCase {
    /// The local notification's text matches which cap was hit, and the reset wording differs (back tomorrow for daily, back Monday for the weekly block).
    func testNotificationTextMatchesCapKind() {
        let daily = freeCapNotificationText(isWeekly: false)
        let weekly = freeCapNotificationText(isWeekly: true)
        XCTAssertTrue(daily.title.lowercased().contains("today"), daily.title)
        XCTAssertTrue(daily.body.lowercased().contains("tomorrow"), daily.body)
        XCTAssertTrue(weekly.title.lowercased().contains("week"), weekly.title)
        XCTAssertTrue(weekly.body.lowercased().contains("monday"), weekly.body)
    }
}
