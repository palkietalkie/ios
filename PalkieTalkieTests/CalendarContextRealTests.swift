import EventKit
@testable import PalkieTalkie
import XCTest

/// Tests the real CalendarContext actor (not just the protocol fake). EventKit in the test bundle has no permission, so
/// every path returns empty. Still exercises the actor surface so its lines aren't dark.
final class CalendarContextRealTests: XCTestCase {
    func testRealCalendarContextRequestAccessDeniedByDefault() async {
        let context = CalendarContext()
        // In the test bundle, EventKit refuses access — the actor swallows the error and returns false.
        let granted = await context.requestAccess()
        XCTAssertFalse(granted)
    }

    func testRealCalendarContextTodaysEventsReturnsEmptyWithoutAccess() async {
        let context = CalendarContext()
        let events = await context.todaysEvents()
        XCTAssertTrue(events.isEmpty, "no permission → no events")
    }

    func testCalendarContextWithInjectedStore() async {
        // The init accepts an EKEventStore so callers can stage a pre-configured one. Verify the actor accepts it.
        let store = EKEventStore()
        let context = CalendarContext(store: store)
        let events = await context.todaysEvents()
        XCTAssertTrue(events.isEmpty)
    }
}
