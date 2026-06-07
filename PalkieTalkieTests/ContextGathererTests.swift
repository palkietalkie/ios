@testable import PalkieTalkie
import XCTest

/// The ContextGatherer fans out four async calls (location, weather, reverse-geocode, calendar) and packages them as
/// `ConversationContext`. We can't easily inject the location stub today (LocationContext is a concrete actor) but we
/// CAN exercise the path where location returns nil — the gatherer must still produce a valid context with default
/// fields.
final class ContextGathererTests: XCTestCase {
    func testGatherProducesNonEmptyTimezoneAndTimeWhenNoLocation() async {
        let gatherer = ContextGatherer(
            location: LocationContext(),
            weather: WeatherContext(fetcher: FakeWeatherFetcher(responseData: Data())),
            calendar: FakeCalendarStore(grantAccess: false, events: []),
        )
        let ctx = await gatherer.gather()
        // Time and timezone come from the device clock and are always populated.
        XCTAssertFalse(ctx.localISOTime.isEmpty)
        XCTAssertFalse(ctx.timezone.isEmpty)
        // No location permission in tests → coordinates and city stay nil.
        XCTAssertNil(ctx.lat)
        XCTAssertNil(ctx.lon)
        XCTAssertNil(ctx.city)
        XCTAssertNil(ctx.weatherDescription)
        XCTAssertNil(ctx.temperatureC)
        // No calendar permission → empty events list.
        XCTAssertTrue(ctx.calendarEvents.isEmpty)
    }

    func testGatherIncludesCalendarEventsWhenGranted() async {
        let event = CalendarEventDTO(
            title: "Standup",
            startISO: "2026-01-01T09:00:00Z",
            endISO: "2026-01-01T09:30:00Z",
            location: nil,
        )
        let gatherer = ContextGatherer(
            location: LocationContext(),
            weather: WeatherContext(fetcher: FakeWeatherFetcher(responseData: Data())),
            calendar: FakeCalendarStore(grantAccess: true, events: [event]),
        )
        let ctx = await gatherer.gather()
        XCTAssertEqual(ctx.calendarEvents.count, 1)
        XCTAssertEqual(ctx.calendarEvents.first?.title, "Standup")
    }

    func testSharedInstanceIsReusable() {
        let a = ContextGatherer.shared
        let b = ContextGatherer.shared
        XCTAssertTrue(a === b)
    }
}
