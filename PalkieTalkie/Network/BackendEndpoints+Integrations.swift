import Foundation

/// External calendar connections: list current status + kick off each provider's OAuth connect flow.
extension BackendAPI {
    func listIntegrations() async throws -> [IntegrationStatus] {
        try await get("/integrations")
    }

    func connectGoogleCalendar() async throws -> OAuthConnectURL {
        struct Empty: Codable {}
        return try await post("/integrations/google-calendar/connect", body: Empty())
    }

    func connectOutlook() async throws -> OAuthConnectURL {
        struct Empty: Codable {}
        return try await post("/integrations/outlook/connect", body: Empty())
    }
}
