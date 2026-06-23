@testable import PalkieTalkie
import XCTest

/// Coverage for the per-feature methods in BackendEndpoints.swift. Each test asserts:
/// - The HTTP method + path is right.
/// - The body (if any) encodes snake_case correctly.
/// - The decoder reads a representative response and surfaces typed fields.
final class BackendEndpointsTests: XCTestCase {
    private func makeAPI(transport: FakeTransport) -> BackendAPI {
        BackendAPI(
            baseURL: URL(string: "https://api.test")!,
            transport: transport,
            auth: StubAuthing(token: "tok"),
        )
    }

    // MARK: - Personas

    func testGetPersonasSendsSortAndSearch() async throws {
        let transport = FakeTransport()
        transport.responseData = Data("[]".utf8)
        let api = makeAPI(transport: transport)
        _ = try await api.getPersonas(search: "wes & co", sort: "popular")
        let url = try XCTUnwrap(transport.lastRequest?.url)
        XCTAssertEqual(url.path, "/personas")
        // Order is sort first, then q — and "&" is percent-encoded.
        XCTAssertTrue(url.query?.contains("sort=popular") == true)
        XCTAssertTrue(url.query?.contains("q=wes") == true)
    }

    func testCreatePersonaPOSTSAndDecodes() async throws {
        let transport = FakeTransport()
        let returned = PersonaDTO(
            id: "p1", name: "Bee", description: "",
            voiceId: "NATM1",
            role: nil, age: nil, background: nil,
            vocabularyRegister: nil, conversationalStyle: nil, topicalPreferences: nil,
            isPreset: false, isPublic: true, isOwner: true,
            likeCount: 0, likedByMe: false,
        )
        transport.responseData = try BackendAPI.encoder.encode(returned)
        let api = makeAPI(transport: transport)
        let payload = PersonaCreatePayload(
            name: "Bee", description: "",
            voiceId: "NATM1",
            role: nil, age: nil, background: nil,
            vocabularyRegister: nil, conversationalStyle: nil, topicalPreferences: nil,
            isPublic: true,
        )
        let created = try await api.createPersona(payload)
        XCTAssertEqual(created.id, "p1")
        XCTAssertEqual(transport.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(transport.lastRequest?.url?.path, "/personas")
        let body = try XCTUnwrap(transport.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["voice_id"] as? String, "NATM1")
        XCTAssertEqual(json["is_public"] as? Bool, true)
    }

    func testUpdatePersonaPATCH() async throws {
        let transport = FakeTransport()
        let returned = PersonaDTO(
            id: "p1", name: "Bee", description: "",
            voiceId: "NATM1",
            role: nil, age: nil, background: nil,
            vocabularyRegister: nil, conversationalStyle: nil, topicalPreferences: nil,
            isPreset: false, isPublic: false, isOwner: true,
            likeCount: 3, likedByMe: true,
        )
        transport.responseData = try BackendAPI.encoder.encode(returned)
        let api = makeAPI(transport: transport)
        let payload = PersonaUpdatePayload(
            name: "Bee", description: nil, voiceId: nil,
            role: nil, age: nil, background: nil,
            vocabularyRegister: nil, conversationalStyle: nil, topicalPreferences: nil,
            isPublic: false,
        )
        _ = try await api.updatePersona(id: "p1", payload)
        XCTAssertEqual(transport.lastRequest?.httpMethod, "PATCH")
        XCTAssertEqual(transport.lastRequest?.url?.path, "/personas/p1")
    }

    func testDeletePersonaDELETE() async throws {
        let transport = FakeTransport()
        transport.responseData = Data("{}".utf8)
        let api = makeAPI(transport: transport)
        try await api.deletePersona(id: "p1")
        XCTAssertEqual(transport.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(transport.lastRequest?.url?.path, "/personas/p1")
    }

    func testDeleteAccountDELETE() async throws {
        let transport = FakeTransport()
        transport.responseData = Data("{}".utf8)
        let api = makeAPI(transport: transport)
        try await api.deleteAccount()
        XCTAssertEqual(transport.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(transport.lastRequest?.url?.path, "/account")
    }

    func testLikeAndUnlikePersona() async throws {
        let transport = FakeTransport()
        transport.responseData = Data("{}".utf8)
        let api = makeAPI(transport: transport)

        try await api.likePersona(id: "p1")
        XCTAssertEqual(transport.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(transport.lastRequest?.url?.path, "/personas/p1/like")

        try await api.unlikePersona(id: "p1")
        XCTAssertEqual(transport.lastRequest?.httpMethod, "DELETE")
        XCTAssertEqual(transport.lastRequest?.url?.path, "/personas/p1/like")
    }

    func testReportPersonaPOST() async throws {
        let transport = FakeTransport()
        transport.responseData = Data("{}".utf8)
        let api = makeAPI(transport: transport)

        try await api.reportPersona(id: "p1")
        XCTAssertEqual(transport.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(transport.lastRequest?.url?.path, "/personas/p1/report")
    }

    // MARK: - Voices / languages / options

    func testGetVoices() async throws {
        let transport = FakeTransport()
        transport.responseData = Data("[]".utf8)
        let api = makeAPI(transport: transport)
        let voices = try await api.getVoices()
        XCTAssertEqual(voices.count, 0)
        XCTAssertEqual(transport.lastRequest?.url?.path, "/voices")
    }

    func testGetLanguages() async throws {
        let transport = FakeTransport()
        transport.responseData = Data("[]".utf8)
        let api = makeAPI(transport: transport)
        _ = try await api.getLanguages()
        XCTAssertEqual(transport.lastRequest?.url?.path, "/languages")
    }

    func testGetPracticeOptions() async throws {
        let transport = FakeTransport()
        let raw = """
        {"proficiency":["beginner","intermediate","advanced"],"tutor_speaking_speed":["slow","normal","fast"],"goals":["everyday_conversation","work_meetings"]}
        """
        transport.responseData = Data(raw.utf8)
        let api = makeAPI(transport: transport)
        let opts = try await api.getPracticeOptions()
        XCTAssertEqual(opts.proficiency, ["beginner", "intermediate", "advanced"])
        XCTAssertEqual(opts.tutorSpeakingSpeed, ["slow", "normal", "fast"])
        XCTAssertEqual(opts.goals, ["everyday_conversation", "work_meetings"])
    }

    // MARK: - Consent

    func testGetConsent() async throws {
        let transport = FakeTransport()
        let raw = """
        {"personalization":true,"product_improvement":false,"set":true}
        """
        transport.responseData = Data(raw.utf8)
        let api = makeAPI(transport: transport)
        let c = try await api.getConsent()
        XCTAssertTrue(c.personalization)
        XCTAssertFalse(c.productImprovement)
        XCTAssertTrue(c.set)
    }

    func testSetConsentPUT() async throws {
        let transport = FakeTransport()
        let raw = """
        {"personalization":true,"product_improvement":true,"set":true}
        """
        transport.responseData = Data(raw.utf8)
        let api = makeAPI(transport: transport)
        let payload = ConsentUpdatePayload(personalization: true, productImprovement: true)
        _ = try await api.setConsent(payload)
        XCTAssertEqual(transport.lastRequest?.httpMethod, "PUT")
        XCTAssertEqual(transport.lastRequest?.url?.path, "/consent")
        let body = try XCTUnwrap(transport.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["product_improvement"] as? Bool, true)
    }

    // MARK: - Stats

    func testGetStats() async throws {
        let transport = FakeTransport()
        let raw = """
        {"day_streak":3,"session_total_seconds":120,"sessions_count":1,"unique_words":50,"unique_phrases":4,"user_talk_pct":null,"speaking_rate_wpm":null,"pitch_min_hz":null,"pitch_max_hz":null,"affinity":42,"cefr_coverage":[]}
        """
        transport.responseData = Data(raw.utf8)
        let api = makeAPI(transport: transport)
        let stats = try await api.getStats()
        XCTAssertEqual(stats.dayStreak, 3)
        XCTAssertEqual(stats.sessionsCount, 1)
        XCTAssertNil(stats.userTalkPct)
        XCTAssertEqual(stats.affinity, 42)
    }

    func testGetMistakesPhrasesCEFR() async throws {
        let transport = FakeTransport()
        transport.responseData = Data("[]".utf8)
        let api = makeAPI(transport: transport)
        _ = try await api.getMistakes()
        XCTAssertEqual(transport.lastRequest?.url?.path, "/stats/mistakes")
        _ = try await api.getPhrases()
        XCTAssertEqual(transport.lastRequest?.url?.path, "/stats/phrases")
        _ = try await api.getCEFRWords(level: "A1")
        XCTAssertEqual(transport.lastRequest?.url?.path, "/stats/cefr")
        XCTAssertEqual(transport.lastRequest?.url?.query, "level=A1")
    }

    // MARK: - Entitlement

    func testGetEntitlement() async throws {
        let transport = FakeTransport()
        let raw = """
        {"is_premium":false,"free_minutes_remaining_today":7,"free_minutes_remaining_this_week":18,"free_minutes_per_day_cap":10,"free_minutes_per_week_cap":30,"premium_ends_at":null}
        """
        transport.responseData = Data(raw.utf8)
        let api = makeAPI(transport: transport)
        let e = try await api.getEntitlement()
        XCTAssertFalse(e.isPremium)
        XCTAssertEqual(e.freeMinutesRemainingToday, 7)
        XCTAssertEqual(e.freeMinutesRemainingThisWeek, 18)
        XCTAssertEqual(e.freeMinutesPerDayCap, 10)
        XCTAssertEqual(e.freeMinutesPerWeekCap, 30)
        XCTAssertNil(e.premiumEndsAt)
    }

    // MARK: - Talk about today

    func testGetTalkAboutTodayMapsItemIds() async throws {
        let transport = FakeTransport()
        let raw = """
        {"day":"2026-01-01","sections":[{"topic":"politics","items":[{"title":"Hello","summary":"World","source":"AP","image_url":"https://example.test/img.png"}]}]}
        """
        transport.responseData = Data(raw.utf8)
        let api = makeAPI(transport: transport)
        let sections = try await api.getTalkAboutToday()
        XCTAssertEqual(sections.count, 1)
        let section = try XCTUnwrap(sections.first)
        XCTAssertEqual(section.topic, "politics")
        XCTAssertEqual(section.items.first?.id, "politics-0-Hello")
        XCTAssertEqual(section.items.first?.title, "Hello")
        XCTAssertEqual(section.items.first?.imageUrl, "https://example.test/img.png")
    }

    // MARK: - KG

    func testGetKG() async throws {
        let transport = FakeTransport()
        transport.responseData = Data(#"{"nodes":[],"edges":[]}"#.utf8)
        let api = makeAPI(transport: transport)
        _ = try await api.getKG()
        XCTAssertEqual(transport.lastRequest?.url?.path, "/kg")
    }

    /// Cross-boundary contract: decode the EXACT JSON `backend/app/services/neo4j/fetch_kg.py` emits — `{nodes:[{id,type,name,attrs}], edges:[{src,rel,dst}]}` with attrs stringified. The old test fed a bare `[]` (iOS-internal shape) which never matched the backend, so the nodes/edges drift slipped through and every user saw an empty KG. Keep this byte-shape in lockstep with fetch_kg.py.
    func testGetKGDecodesBackendWireShape() async throws {
        let backendJSON = """
        {
          "nodes": [
            {"id": "Naoto", "type": "person", "name": "Naoto", "attrs": {"relation": "brother", "age": "34"}},
            {"id": "Coventry", "type": "place", "name": "Coventry", "attrs": {}}
          ],
          "edges": [
            {"src": "Naoto", "rel": "LIVES_IN", "dst": "Coventry"}
          ]
        }
        """
        let transport = FakeTransport()
        transport.responseData = Data(backendJSON.utf8)
        let api = makeAPI(transport: transport)
        let graph = try await api.getKG()
        XCTAssertEqual(graph.nodes.count, 2)
        XCTAssertEqual(graph.nodes.first?.name, "Naoto")
        XCTAssertEqual(graph.nodes.first?.attrs["relation"], "brother")
        XCTAssertEqual(graph.nodes.first?.attrs["age"], "34")
        XCTAssertEqual(graph.edges.count, 1)
        XCTAssertEqual(graph.edges.first?.rel, "LIVES_IN")
        XCTAssertEqual(graph.edges.first?.dst, "Coventry")
    }

    // MARK: - Recall (realtime tool outputs)

    func testRecallFactsFormatsEntitiesAndRelations() async throws {
        let transport = FakeTransport()
        transport.responseData = Data(#"""
        {"entities":[{"name":"Naoto","type":"person","relations":[{"rel":"WORKS_AT","target":"Kawasaki"}]}]}
        """#.utf8)
        let api = makeAPI(transport: transport)
        let out = try await api.recallFacts(query: "naoto")
        XCTAssertEqual(out, "Naoto (person): WORKS_AT Kawasaki")
        XCTAssertEqual(transport.lastRequest?.url?.path, "/recall/facts")
    }

    func testRecallFactsEmptyGivesReadableNote() async throws {
        let transport = FakeTransport()
        transport.responseData = Data(#"{"entities":[]}"#.utf8)
        let api = makeAPI(transport: transport)
        let out = try await api.recallFacts(query: "nobody")
        XCTAssertEqual(out, "No matching facts found.")
    }

    func testRecallConversationsJoinsSnippets() async throws {
        let transport = FakeTransport()
        transport.responseData = Data(#"{"snippets":["talked about interviews","talked about climbing"]}"#.utf8)
        let api = makeAPI(transport: transport)
        let out = try await api.recallConversations(query: "interview")
        XCTAssertEqual(out, "talked about interviews\ntalked about climbing")
    }

    func testSearchTranscriptsFormatsTurns() async throws {
        let transport = FakeTransport()
        transport.responseData = Data(#"""
        {"turns":[{"speaker":"user","text":"I love bouldering","when":"2026-01-01T00:00:00Z"}]}
        """#.utf8)
        let api = makeAPI(transport: transport)
        let out = try await api.searchTranscripts(query: "bouldering")
        XCTAssertEqual(out, "user: I love bouldering")
    }

    // MARK: - Profile

    func testGetAndUpdateProfile() async throws {
        let transport = FakeTransport()
        let profile = ProfileDTO(
            email: "x@y.test",
            preferredName: "Wes",
            namePronunciation: nil,
            namePronunciationSuggestion: nil,
            nativeLanguages: ["Japanese"],
            targetLanguage: "English",
            targetAccents: ["American"],
            proficiency: "intermediate",
            tutorSpeakingSpeed: "normal",
            goals: nil,
            locationCity: nil,
            timezone: nil,
        )
        transport.responseData = try BackendAPI.encoder.encode(profile)
        let api = makeAPI(transport: transport)
        let got = try await api.getProfile()
        XCTAssertEqual(got.preferredName, "Wes")
        XCTAssertEqual(transport.lastRequest?.url?.path, "/profile")

        let update = ProfileUpdate(
            preferredName: "Wes", namePronunciation: nil,
            nativeLanguages: ["Japanese"], targetLanguage: "English",
            targetAccents: ["American", "British"], proficiency: nil, tutorSpeakingSpeed: nil,
            goals: nil, locationCity: nil, timezone: nil,
        )
        _ = try await api.updateProfile(update)
        XCTAssertEqual(transport.lastRequest?.httpMethod, "PATCH")
    }

    // MARK: - Push token

    func testRegisterPushTokenSendsApnsToken() async throws {
        let transport = FakeTransport()
        transport.responseData = Data("{}".utf8)
        let api = makeAPI(transport: transport)
        try await api.registerPushToken("deadbeef")
        XCTAssertEqual(transport.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(transport.lastRequest?.url?.path, "/devices/apns")
        let body = try XCTUnwrap(transport.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["apns_token"] as? String, "deadbeef")
    }

    // MARK: - Events

    func testRecordColdStartIncludesEventType() async throws {
        let transport = FakeTransport()
        transport.responseData = Data("{}".utf8)
        let api = makeAPI(transport: transport)
        let timings = ColdStartTimings(
            gatherContextMs: 100, backendStartMs: 200,
            websocketConnectMs: 300, firstAudioMs: 400,
        )
        try await api.recordColdStart(durationMs: 1000, phaseTimings: timings, sessionId: "S-9")
        XCTAssertEqual(transport.lastRequest?.url?.path, "/events")
        let body = try XCTUnwrap(transport.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["event_type"] as? String, "cold_start_complete")
        let props = try XCTUnwrap(json["props"] as? [String: Any])
        XCTAssertEqual(props["duration_ms"] as? Int, 1000)
        XCTAssertEqual(props["session_id"] as? String, "S-9")
        let phase = try XCTUnwrap(props["phase_timings"] as? [String: Any])
        XCTAssertEqual(phase["first_audio_ms"] as? Int, 400)
    }

    func testRecordPitchRangeIncludesEventType() async throws {
        let transport = FakeTransport()
        transport.responseData = Data("{}".utf8)
        let api = makeAPI(transport: transport)
        try await api.recordPitchRange(sessionId: "S-10", minHz: 120.5, maxHz: 240.7)
        XCTAssertEqual(transport.lastRequest?.url?.path, "/events")
        let body = try XCTUnwrap(transport.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["event_type"] as? String, "pitch_range")
    }

    func testRecordAIEmotionsPostsPerCategoryCounts() async throws {
        let transport = FakeTransport()
        transport.responseData = Data("{}".utf8)
        let api = makeAPI(transport: transport)
        try await api.recordAIEmotions(sessionId: "S-11", laugh: 3, cheer: 1, gasp: 0, sigh: 2, groan: 1)
        XCTAssertEqual(transport.lastRequest?.url?.path, "/events")
        let body = try XCTUnwrap(transport.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["event_type"] as? String, "ai_emotion")
        let props = try XCTUnwrap(json["props"] as? [String: Any])
        XCTAssertEqual(props["laugh"] as? Int, 3)
        XCTAssertEqual(props["sigh"] as? Int, 2)
    }

    // MARK: - Integrations

    func testListIntegrations() async throws {
        let transport = FakeTransport()
        transport.responseData = Data("[]".utf8)
        let api = makeAPI(transport: transport)
        _ = try await api.listIntegrations()
        XCTAssertEqual(transport.lastRequest?.url?.path, "/integrations")
    }

    func testConnectGoogleCalendarAndOutlookPOST() async throws {
        let transport = FakeTransport()
        transport.responseData = Data(#"{"auth_url":"https://accounts.google.com/o/oauth2/auth"}"#.utf8)
        let api = makeAPI(transport: transport)
        let google = try await api.connectGoogleCalendar()
        XCTAssertEqual(transport.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(transport.lastRequest?.url?.path, "/integrations/google-calendar/connect")
        XCTAssertEqual(google.authUrl, "https://accounts.google.com/o/oauth2/auth")

        transport.responseData = Data(#"{"auth_url":"https://login.microsoftonline.com"}"#.utf8)
        let outlook = try await api.connectOutlook()
        XCTAssertEqual(transport.lastRequest?.url?.path, "/integrations/outlook/connect")
        XCTAssertEqual(outlook.authUrl, "https://login.microsoftonline.com")
    }

    // MARK: - Sessions / transcripts / conversation lifecycle

    func testGetSessionsAppendsLimit() async throws {
        let transport = FakeTransport()
        transport.responseData = Data("[]".utf8)
        let api = makeAPI(transport: transport)
        _ = try await api.getSessions(limit: 25)
        XCTAssertEqual(transport.lastRequest?.url?.path, "/conversation/sessions")
        XCTAssertEqual(transport.lastRequest?.url?.query, "limit=25")
    }

    func testEndConversation() async throws {
        let transport = FakeTransport()
        transport.responseData = Data(#"{"session_id":"s1","duration_seconds":42}"#.utf8)
        let api = makeAPI(transport: transport)
        let resp = try await api.endConversation(sessionId: "s1")
        XCTAssertEqual(resp.durationSeconds, 42)
        XCTAssertEqual(transport.lastRequest?.url?.path, "/conversation/s1/end")
        XCTAssertEqual(transport.lastRequest?.httpMethod, "POST")
    }

    func testAppendTranscriptPostsTurn() async throws {
        let transport = FakeTransport()
        transport.responseData = Data("{}".utf8)
        let api = makeAPI(transport: transport)
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let end = start.addingTimeInterval(2)
        try await api.appendTranscript(
            sessionId: "s1",
            speaker: "user",
            text: "hello",
            startedAt: start,
            endedAt: end,
        )
        XCTAssertEqual(transport.lastRequest?.url?.path, "/conversation/s1/transcript")
        let body = try XCTUnwrap(transport.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["speaker"] as? String, "user")
        XCTAssertEqual(json["text"] as? String, "hello")
        XCTAssertNotNil(json["started_at"])
        XCTAssertNotNil(json["ended_at"])
    }

    func testUploadSessionAudioSendsRawBytes() async throws {
        let transport = FakeTransport()
        transport.responseData = Data() // 200 with empty body is fine for raw POST
        let api = makeAPI(transport: transport)
        let payload = Data([0x1F, 0x8B, 0x08, 0x00]) // arbitrary opaque bytes for transport-level assertions
        try await api.uploadMicAudio(sessionId: "s1", deflatedWav: payload)
        XCTAssertEqual(transport.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(transport.lastRequest?.url?.path, "/conversation/s1/audio/mic")
        // Regression: pre-fix builds sent "audio/wav+gzip" but the bytes were raw DEFLATE (Apple's `NSData.compressed(using: .zlib)` despite its name). The decoder couldn't gunzip and fell through to garbage interpretation of compressed bytes as PCM. Lock the truthful label so the bug can't sneak back.
        XCTAssertEqual(transport.lastRequest?.value(forHTTPHeaderField: "Content-Type"), "audio/wav+deflate")
        XCTAssertEqual(transport.lastRequest?.httpBody, payload)
    }
}
