import Foundation

/// Per-feature methods that compose calls on `BackendAPI`. Splitting the surface here keeps `BackendAPI` focused on transport / encoding / decoding so each side can be tested independently.
extension BackendAPI {
    func startConversation(
        personaId: String,
        context: ConversationContext,
        topicOverride: String? = nil,
    ) async throws -> StartResponse {
        // Backend's StartRequest accepts persona_id, lat, lon, topic_override.
        // Other ConversationContext fields (timezone, city, weather, calendar) are re-derived server-side from the user's stored profile + integrations.
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
                topicOverride: topicOverride,
            ),
        )
    }

    func getSessions(limit: Int = 100) async throws -> [SessionSummary] {
        try await get("/conversation/sessions?limit=\(limit)")
    }

    func endConversation(sessionId: String) async throws -> EndResponse {
        struct Empty: Codable {}
        return try await post("/conversation/\(sessionId)/end", body: Empty())
    }

    /// Append one TURN — one continuous block of speech from one speaker. Caller (SessionController) aggregates stream fragments and only POSTs when the speaker switches or the session ends. Natural key is (session_id, speaker, started_at).
    func appendTranscript(
        sessionId: String,
        speaker: String,
        text: String,
        startedAt: Date,
        endedAt: Date,
    ) async throws {
        let body = TranscriptAppend(speaker: speaker, text: text, startedAt: startedAt, endedAt: endedAt)
        let _: EmptyResponse = try await post("/conversation/\(sessionId)/transcript", body: body)
    }

    func getPersonas(search: String? = nil, sort: String = "recommended") async throws -> [PersonaDTO] {
        // Preset name/description are localized server-side (backend owns that content), so tell the backend which UI language we're rendering in.
        let lang = Bundle.main.preferredLocalizations.first ?? "en"
        var query = "sort=\(sort)&lang=\(lang)"
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

    func getLanguages() async throws -> [LanguageDTO] {
        try await get("/languages")
    }

    func getPracticeOptions() async throws -> PracticeOptionsDTO {
        try await get("/profile/practice-options")
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

    func getTalkAboutToday() async throws -> [TalkSection] {
        let payload: DailyContentDTO = try await get("/content/today")
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

    func getKG() async throws -> KGGraphDTO {
        try await get("/kg")
    }

    // MARK: - Conversation-time recall (realtime tool calls)

    private func encodeQuery(_ q: String) -> String {
        q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
    }

    func recallFacts(query: String) async throws -> String {
        let dto: RecallFactsDTO = try await get("/recall/facts?q=\(encodeQuery(query))")
        guard !dto.entities.isEmpty else { return "No matching facts found." }
        return dto.entities.map { entity in
            let rels = entity.relations
                .map { "\($0.rel ?? "related to") \($0.target)" }
                .joined(separator: "; ")
            return rels.isEmpty ? "\(entity.name) (\(entity.type))" : "\(entity.name) (\(entity.type)): \(rels)"
        }.joined(separator: "\n")
    }

    func recallConversations(query: String) async throws -> String {
        let dto: RecallConversationsDTO = try await get("/recall/conversations?q=\(encodeQuery(query))")
        return dto.snippets.isEmpty ? "No relevant past conversations." : dto.snippets.joined(separator: "\n")
    }

    func searchTranscripts(query: String) async throws -> String {
        let dto: RecallTranscriptsDTO = try await get("/recall/transcripts?q=\(encodeQuery(query))")
        guard !dto.turns.isEmpty else { return "No matching past words found." }
        return dto.turns.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
    }

    func webFetch(url: String) async throws -> String {
        let dto: WebFetchDTO = try await get("/recall/web_fetch?url=\(encodeQuery(url))")
        return dto.content.isEmpty ? "Couldn't read that page." : dto.content
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
        sessionId: String,
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
                    sessionId: sessionId,
                ),
            ),
        )
    }

    func recordPitchRange(sessionId: String, minHz: Float, maxHz: Float) async throws {
        struct Props: Codable {
            let sessionId: String
            let minHz: Float
            let maxHz: Float
        }
        struct Body: Codable {
            let eventType: String
            let props: Props
        }
        let _: EmptyResponse = try await post(
            "/events",
            body: Body(
                eventType: "pitch_range",
                props: Props(sessionId: sessionId, minHz: minHz, maxHz: maxHz),
            ),
        )
    }

    /// Per-category counts of the tutor's reactions this session (detected live on-device): positives (laugh/cheer/gasp) and negatives (sigh/groan). Stored as one event row, the saved per-user record we also mine internally for struggling users. `/stats` weights and combines them (negatives subtract) into the Affinity metric. Weights live server-side so the formula stays tunable without an app update.
    func recordAIEmotions(
        sessionId: String, laugh: Int, cheer: Int, gasp: Int, sigh: Int, groan: Int,
    ) async throws {
        struct Props: Codable {
            let sessionId: String
            let laugh: Int
            let cheer: Int
            let gasp: Int
            let sigh: Int
            let groan: Int
        }
        struct Body: Codable {
            let eventType: String
            let props: Props
        }
        let _: EmptyResponse = try await post(
            "/events",
            body: Body(
                eventType: "ai_emotion",
                props: Props(
                    sessionId: sessionId, laugh: laugh, cheer: cheer, gasp: gasp, sigh: sigh, groan: groan,
                ),
            ),
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

    /// Upload the deflate-compressed wav of the iOS MIC recording (post-acoustic-echo-cancellation user-side audio). The paired `uploadModelAudio` ships the AI's raw output for the same session.
    func uploadMicAudio(sessionId: String, deflatedWav: Data) async throws {
        // Content type is "audio/wav+deflate" (raw DEFLATE), NOT "audio/wav+gzip". Apple's `NSData.compressed(using: .zlib)` produces a raw deflate stream with no gzip header or trailer; mislabelling broke the backend's decoder.
        try await postRaw(
            "/conversation/\(sessionId)/audio/mic",
            body: deflatedWav,
            contentType: "audio/wav+deflate",
        )
    }

    /// Upload the AI's raw PCM16 output (deflate-compressed wav) — what arrived from OpenAI Realtime *before* iOS played it through the speaker. Lets us tell whether audio truncation like "Wes" → "We" happens in iOS playback or in the model's stream.
    func uploadModelAudio(sessionId: String, deflatedWav: Data) async throws {
        try await postRaw(
            "/conversation/\(sessionId)/audio/model",
            body: deflatedWav,
            contentType: "audio/wav+deflate",
        )
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
