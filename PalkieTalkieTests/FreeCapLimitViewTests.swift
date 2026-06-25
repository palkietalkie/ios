@testable import PalkieTalkie
import ViewInspector
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

    /// nil onUpgrade (no paid tier to sell) must hide the Upgrade button — a button that opens an empty IAP screen is the App Review 2.1(b) failure we're avoiding.
    func testUpgradeButtonHiddenWhenNoUpgradeHandler() throws {
        let sut = FreeCapLimitView(limitKind: "daily", onUpgrade: nil, onDismiss: {})
        XCTAssertThrowsError(try sut.inspect().find(button: "Upgrade"))
        // "Not now" is always present so the user can still dismiss the cover.
        XCTAssertNoThrow(try sut.inspect().find(button: "Not now"))
    }

    /// A non-nil onUpgrade wires the Upgrade button — the path used once paid tiers are live.
    func testUpgradeButtonShownWhenUpgradeHandlerPresent() throws {
        let sut = FreeCapLimitView(limitKind: "daily", onUpgrade: {}, onDismiss: {})
        XCTAssertNoThrow(try sut.inspect().find(button: "Upgrade"))
    }
}
