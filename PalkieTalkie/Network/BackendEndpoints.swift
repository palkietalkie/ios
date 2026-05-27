import Foundation

/// Per-feature methods that compose calls on `BackendAPI`. Splitting the surface here keeps `BackendAPI` focused on
/// transport / encoding / decoding so each side can be tested independently.
extension BackendAPI {
    func startConversation(
        personaId: String,
        context: ConversationContext,
        topicOverride: String? = nil
    ) async throws -> StartResponse {
        // Backend's StartRequest accepts persona_id, lat, lon, topic_override.
        // Other ConversationContext fields (timezone, city, weather, calendar) are re-derived server-side from the
        // user's stored profile + integrations.
        struct Body: Codable {
            let personaId: String
            let lat: Double?
            let lon: Double?
            let topicOverride: String?
        }
        return try await post(
            "/conversation/start",
            body: Body(
                personaId: personaId,
                lat: context.lat,
                lon: context.lon,
                topicOverride: topicOverride
            )
        )
    }

    func getSessions(limit: Int = 100) async throws -> [SessionSummary] {
        try await get("/conversation/sessions?limit=\(limit)")
    }

    func endConversation(sessionId: String) async throws -> EndResponse {
        struct Empty: Codable {}
        return try await post("/conversation/\(sessionId)/end", body: Empty())
    }

    /// Append one TURN — one continuous block of speech from one speaker. Caller (SessionController) aggregates stream
    /// fragments and only POSTs when the speaker switches or the session ends. Natural key is (session_id, speaker,
    /// started_at).
    func appendTranscript(
        sessionId: String,
        speaker: String,
        text: String,
        startedAt: Date,
        endedAt: Date
    ) async throws {
        let body = TranscriptAppend(speaker: speaker, text: text, startedAt: startedAt, endedAt: endedAt)
        let _: EmptyResponse = try await post("/conversation/\(sessionId)/transcript", body: body)
    }

    func getPersonas(search: String? = nil, sort: String = "recommended") async throws -> [PersonaDTO] {
        var query = "sort=\(sort)"
        if let search, !search.isEmpty {
            let encoded = search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? search
            query += "&q=\(encoded)"
        }
        return try await get("/personas?\(query)")
    }

    func createPersona(_ payload: PersonaCreatePayload) async throws -> PersonaDTO {
        try await post("/personas", body: payload)
    }

    func updatePersona(id: String, _ payload: PersonaUpdatePayload) async throws -> PersonaDTO {
        try await patch("/personas/\(id)", body: payload)
    }

    func deletePersona(id: String) async throws {
        let _: EmptyResponse = try await delete("/personas/\(id)")
    }

    func likePersona(id: String) async throws {
        struct Empty: Codable {}
        let _: EmptyResponse = try await post("/personas/\(id)/like", body: Empty())
    }

    func unlikePersona(id: String) async throws {
        let _: EmptyResponse = try await delete("/personas/\(id)/like")
    }

    func getVoices() async throws -> [VoiceDTO] {
        try await get("/voices")
    }

    func getConsent() async throws -> ConsentDTO {
        try await get("/consent")
    }

    func setConsent(_ payload: ConsentUpdatePayload) async throws -> ConsentDTO {
        try await put("/consent", body: payload)
    }

    func getStats() async throws -> Stats {
        try await get("/stats")
    }

    func getMistakes() async throws -> [Mistake] {
        try await get("/stats/mistakes")
    }

    func getPhrases() async throws -> [PhraseUsage] {
        try await get("/stats/phrases")
    }

    func getCEFRWords(level: String) async throws -> [CEFRWord] {
        try await get("/stats/cefr?level=\(level)")
    }

    func getEntitlement() async throws -> Entitlement {
        try await get("/entitlement")
    }

    func getTalkAboutToday() async throws -> [TalkPrompt] {
        try await get("/content/today")
    }

    func getKG() async throws -> [KGEntityDTO] {
        try await get("/kg")
    }

    func getProfile() async throws -> ProfileDTO {
        try await get("/profile")
    }

    func updateProfile(_ update: ProfileUpdate) async throws -> ProfileDTO {
        try await patch("/profile", body: update)
    }

    func registerPushToken(_ apnsToken: String) async throws {
        struct Body: Codable { let apnsToken: String }
        let _: EmptyResponse = try await post("/devices/apns", body: Body(apnsToken: apnsToken))
    }

    /// Cold-start telemetry. Fire-and-forget — failures shouldn't abort the conversation.
    func recordColdStart(
        durationMs: Int,
        phaseTimings: ColdStartTimings,
        sessionId: String
    ) async throws {
        struct Props: Codable {
            let durationMs: Int
            let phaseTimings: ColdStartTimings
            let sessionId: String
        }
        struct Body: Codable {
            let eventType: String
            let props: Props
        }
        let _: EmptyResponse = try await post(
            "/events",
            body: Body(
                eventType: "cold_start_complete",
                props: Props(
                    durationMs: durationMs,
                    phaseTimings: phaseTimings,
                    sessionId: sessionId
                )
            )
        )
    }

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

/// Per-phase milliseconds for one cold-start. Sums roughly to total minus parallelism gaps. Backend stores these in
/// `events.props` for percentile analysis across users.
struct ColdStartTimings: Codable {
    let gatherContextMs: Int
    let backendStartMs: Int
    let websocketConnectMs: Int
    let firstAudioMs: Int
}
