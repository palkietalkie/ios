import Foundation

/// Standalone lookups + small singletons that don't warrant their own file: code-defined catalogs (voices, languages), consent, entitlement, daily content, and APNs token registration.
extension BackendAPI {
    func getVoices() async throws -> [VoiceDTO] {
        try await get("/voices")
    }

    func getLanguages() async throws -> [LanguageDTO] {
        try await get("/languages")
    }

    func getConsent() async throws -> ConsentDTO {
        try await get("/consent")
    }

    func setConsent(_ payload: ConsentUpdatePayload) async throws -> ConsentDTO {
        try await put("/consent", body: payload)
    }

    func getNotificationPrefs() async throws -> NotificationPrefsOut {
        try await get("/notification-prefs")
    }

    func setNotificationPrefs(_ payload: NotificationPrefsUpdate) async throws -> NotificationPrefsOut {
        try await put("/notification-prefs", body: payload)
    }

    func getEntitlement() async throws -> Entitlement {
        try await get("/entitlement")
    }

    func getTalkAboutToday() async throws -> [TalkSection] {
        let payload: DailyContentResponse = try await get("/content/today")
        return payload.sections.map { raw in
            let items = raw.items.enumerated().map { idx, item in
                TalkItem(
                    id: "\(raw.topic)-\(idx)-\(item.title)",
                    title: item.title,
                    summary: item.summary,
                    source: item.source,
                    imageUrl: item.imageUrl,
                    url: item.url,
                    details: item.details,
                )
            }
            return TalkSection(topic: raw.topic, items: items)
        }
    }

    func registerPushToken(_ apnsToken: String) async throws {
        struct Body: Codable { let apnsToken: String }
        let _: EmptyResponse = try await post("/devices/apns", body: Body(apnsToken: apnsToken))
    }
}
