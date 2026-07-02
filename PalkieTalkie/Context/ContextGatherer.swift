import Foundation

/// Thin assembler. The actual permission / geocoding / EventKit work lives in `LocationContext` and `CalendarContext`. This type fans out the concurrent requests (device location + reverse-geocode + today's calendar), adds the device clock, and packages them into the wire-shape `ConversationContext` the backend expects.
actor ContextGatherer {
    static let shared = ContextGatherer()

    private let location: LocationContext
    private let calendar: CalendarStoreType

    init(
        location: LocationContext = LocationContext(),
        calendar: CalendarStoreType = CalendarContext(),
    ) {
        self.location = location
        self.calendar = calendar
    }

    func gather() async -> ConversationContext {
        async let resolvedLocation: LocationFix? = location.requestOnce()
        async let calendarEvents = calendar.todaysEvents()

        let now = Date()
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fix = await resolvedLocation
        let city: String? = if let fix {
            await location.reverseGeocode(fix)
        } else {
            nil
        }
        let events = await calendarEvents

        return ConversationContext(
            localISOTime: isoFormatter.string(from: now),
            timezone: TimeZone.current.identifier,
            lat: fix?.latitude,
            lon: fix?.longitude,
            city: city,
            calendarEvents: events,
        )
    }
}
