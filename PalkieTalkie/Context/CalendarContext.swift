import EventKit
import Foundation

/// EventKit seam. Production uses `EKEventStore`; tests inject a fake.
/// Returning `CalendarEventDTO` (the wire shape) lets the test bypass EKEvent construction entirely — `EKEvent`
/// requires a real store.
protocol CalendarStoreType: Sendable {
    func requestAccess() async -> Bool
    func todaysEvents() async -> [CalendarEventDTO]
}

actor CalendarContext: CalendarStoreType {
    private let store: EKEventStore

    init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    /// Returns today's events ONLY if Calendar permission is already granted. Does NOT prompt — permission requests are
    /// user-initiated via Integrations.
    func todaysEvents() async -> [CalendarEventDTO] {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess else { return [] }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? Date()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let formatter = ISO8601DateFormatter()
        return store.events(matching: predicate).map { event in
            CalendarEventDTO(
                title: event.title ?? "",
                startISO: formatter.string(from: event.startDate),
                endISO: formatter.string(from: event.endDate),
                location: event.location
            )
        }
    }
}
