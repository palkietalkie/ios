@testable import PalkieTalkie
import XCTest

final class LocalizedGoalNameTests: XCTestCase {
    func testKnownSlugMapsToNonEmptyLabel() {
        // A known backend slug resolves to a human label (never the raw slug, never empty).
        let label = localizedGoalLabel("work_meetings")
        XCTAssertFalse(label.isEmpty)
        XCTAssertNotEqual(label, "work_meetings")
    }

    func testUnknownSlugFallsBackToItself() {
        // Forward-compat: a slug the app doesn't know (backend added a new goal) degrades to itself, never empty.
        let unknown = "brand_new_goal_xyz"
        XCTAssertEqual(localizedGoalLabel(unknown), unknown)
    }

    func testFreeTextOtherEntryPassesThrough() {
        // The user's free-text "Other" goal isn't a preset slug, so it must round-trip unchanged.
        let other = "Negotiating my rent in person"
        XCTAssertEqual(localizedGoalLabel(other), other)
    }
}
