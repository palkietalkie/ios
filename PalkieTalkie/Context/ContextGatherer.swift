import Foundation

/// Thin assembler. The actual permission / geocoding / weather / EventKit work lives in `LocationContext`,
/// `WeatherContext`, `CalendarContext`. This type only fans out the four concurrent requests and packages the result
/// into the wire-shape `ConversationContext` the backend expects.
actor ContextGatherer {
    static let shared = ContextGatherer()

    private let location: LocationContext
    private let weather: WeatherContext
    private let calendar: CalendarStoreType

    init(
        location: LocationContext = LocationContext(),
        weather: WeatherContext = WeatherContext(),
        calendar: CalendarStoreType = CalendarContext(),
    ) {
        self.location = location
        self.weather = weather
        self.calendar = calendar
    }

    func gather() async -> ConversationContext {
        async let resolvedLocation: LocationFix? = location.requestOnce()
        async let calendarEvents = calendar.todaysEvents()

        let now = Date()
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fix = await resolvedLocation
        let weatherReading: WeatherReading?
        let city: String?
        if let fix {
            async let reading = weather.current(lat: fix.latitude, lon: fix.longitude)
            async let cityName = location.reverseGeocode(fix)
            weatherReading = await reading
            city = await cityName
        } else {
            weatherReading = nil
            city = nil
        }
        let events = await calendarEvents

        return ConversationContext(
            localISOTime: isoFormatter.string(from: now),
            timezone: TimeZone.current.identifier,
            lat: fix?.latitude,
            lon: fix?.longitude,
            city: city,
            weatherDescription: weatherReading?.description,
            temperatureC: weatherReading?.temperatureC,
            calendarEvents: events,
        )
    }
}
