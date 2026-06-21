import Foundation

/// Conversation lifecycle + per-session uploads. Composes calls on `BackendAPI` (transport / encoding / decoding stays in BackendAPI so each side tests independently).
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
