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
}
