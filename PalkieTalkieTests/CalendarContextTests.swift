@testable import PalkieTalkie
import XCTest

actor FakeCalendarStore: CalendarStoreType {
    var grantAccess: Bool
    var events: [CalendarEventDTO]

    init(grantAccess: Bool, events: [CalendarEventDTO]) {
        self.grantAccess = grantAccess
        self.events = events
    }

    func requestAccess() async -> Bool {
        grantAccess
    }

    func todaysEvents() async -> [CalendarEventDTO] {
        grantAccess ? events : []
    }
}

final class CalendarContextTests: XCTestCase {
    func testEventsReturnedWhenGranted() async {
        let store = FakeCalendarStore(
            grantAccess: true,
            events: [
                CalendarEventDTO(
                    title: "Standup",
                    startISO: "2025-01-01T09:00:00Z",
                    endISO: "2025-01-01T09:30:00Z",
                    location: "Zoom"
                )
            ]
        )
        let events = await store.todaysEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.title, "Standup")
    }

    func testNoEventsWhenAccessDenied() async {
        let store = FakeCalendarStore(grantAccess: false, events: [
            CalendarEventDTO(title: "x", startISO: "a", endISO: "b", location: nil)
        ])
        let events = await store.todaysEvents()
        XCTAssertTrue(events.isEmpty)
    }
}
