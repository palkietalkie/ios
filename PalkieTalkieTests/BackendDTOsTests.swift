@testable import PalkieTalkie
import XCTest

/// Snake-case wire-shape round-trip tests for the DTOs `BackendDTOs.swift` defines. The full per-endpoint coverage lives in `BackendEndpointsTests`; this file pairs the DTO source file so the CI test-pair check accepts the extraction.
final class BackendDTOsTests: XCTestCase {
    func testStatsAndTalkItemNewFieldsRoundTripSnakeCase() throws {
        let stats = Stats(
            dayStreak: 3, sessionTotalSeconds: 600, sessionsCount: 4,
            uniqueWords: 50, uniquePhrases: 7, userTalkPct: 0.5, speakingRateWpm: 120,
            pitchMinHz: 90, pitchMaxHz: 230, affinity: 38, cefrCoverage: [],
        )
        let statsData = try BackendAPI.encoder.encode(stats)
        let statsJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: statsData) as? [String: Any])
        XCTAssertEqual(statsJSON["pitch_min_hz"] as? Double, 90)
        XCTAssertEqual(statsJSON["pitch_max_hz"] as? Double, 230)
        XCTAssertEqual(statsJSON["affinity"] as? Int, 38)
        let decodedStats = try BackendAPI.decoder.decode(Stats.self, from: statsData)
        XCTAssertEqual(decodedStats.affinity, 38)
        XCTAssertEqual(decodedStats.pitchMinHz, 90)

        let item = TalkItem(
            id: "i", title: "T", summary: "s", source: "AP", imageUrl: "", url: "https://x", details: "BODY",
        )
        let decodedItem = try BackendAPI.decoder.decode(TalkItem.self, from: BackendAPI.encoder.encode(item))
        XCTAssertEqual(decodedItem.details, "BODY")
        XCTAssertEqual(decodedItem.url, "https://x")
    }

    func testStartResponseRoundTripsThroughSnakeCaseJSON() throws {
        let original = StartResponse(
            sessionId: "srv-1",
            textPrompt: "be a friend",
            voiceId: "alloy",
            wsUrl: "wss://example.test",
            provider: "openai",
            ephemeralToken: "ek_test",
            freeSecondsRemaining: nil,
            freeLimitKind: nil,
        )
        let data = try BackendAPI.encoder.encode(original)
        // Verify the wire format actually used snake_case (camelCase would crash the backend's pydantic parsing).
        let jsonString = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(jsonString.contains("session_id"))
        XCTAssertTrue(jsonString.contains("ws_url"))
        XCTAssertFalse(jsonString.contains("sessionId"))
        let decoded = try BackendAPI.decoder.decode(StartResponse.self, from: data)
        XCTAssertEqual(decoded.sessionId, "srv-1")
        XCTAssertEqual(decoded.provider, "openai")
    }

    func testSessionSummaryUsesSessionIdAsIdentifiable() {
        let summary = SessionSummary(
            sessionId: "abc",
            personaId: nil,
            personaName: nil,
            startedAt: Date(),
            endedAt: nil,
            durationSeconds: nil,
        )
        XCTAssertEqual(summary.id, "abc", "Identifiable id must be sessionId so SwiftUI lists key by it")
    }

    /// The `/kg` payload is `{nodes, edges}`, not a bare `[KGEntityDTO]`. An earlier build decoded the bare array, silently failed, and showed every user an empty graph even when populated. This pins the wrapped shape decodes and that the edge's synthesized Identifiable id is `src|rel|dst`.
    func testKGGraphDecodesNodesAndEdgesAndEdgeID() throws {
        let json = """
        {
          "nodes": [
            {"id": "n1", "type": "person", "name": "Ayumi", "attrs": {"role": "friend"}}
          ],
          "edges": [
            {"src": "n1", "rel": "works_at", "dst": "n2"}
          ]
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let graph = try BackendAPI.decoder.decode(KGGraphDTO.self, from: data)
        XCTAssertEqual(graph.nodes.count, 1)
        XCTAssertEqual(graph.nodes.first?.name, "Ayumi")
        XCTAssertEqual(graph.nodes.first?.attrs["role"], "friend")
        XCTAssertEqual(graph.edges.count, 1)
        XCTAssertEqual(
            graph.edges.first?.id,
            "n1|works_at|n2",
            "edge id must be src|rel|dst for stable SwiftUI list keying",
        )
    }

    /// Recall payloads (`recall.py`) nest entity → relations and transcript turns. Decode the full shape so a wire-name drift (e.g. `target` → `to`) is caught here rather than surfacing as the model getting empty recall mid-conversation.
    func testRecallFactsAndTranscriptsRoundTrip() throws {
        let factsJSON = """
        {"entities": [{"name": "freee", "type": "company", "relations": [{"rel": "works_at", "target": "Ayumi"}]}]}
        """
        let facts = try BackendAPI.decoder.decode(RecallFactsDTO.self, from: XCTUnwrap(factsJSON.data(using: .utf8)))
        XCTAssertEqual(facts.entities.first?.relations.first?.target, "Ayumi")
        XCTAssertEqual(facts.entities.first?.relations.first?.rel, "works_at")

        let turnsJSON = """
        {"turns": [{"speaker": "user", "text": "hi", "when": "2026-06-01T09:00:00Z"}]}
        """
        let transcripts = try BackendAPI.decoder.decode(
            RecallTranscriptsDTO.self,
            from: XCTUnwrap(turnsJSON.data(using: .utf8)),
        )
        XCTAssertEqual(transcripts.turns.first?.speaker, "user")
        XCTAssertEqual(transcripts.turns.first?.text, "hi")
    }

    func testBackendErrorErrorDescriptionsFormatHumanReadable() {
        XCTAssertEqual(BackendError.invalidURL.errorDescription, "Invalid backend URL")
        XCTAssertEqual(BackendError.notAuthenticated(reason: "no jwt").errorDescription, "Not signed in (no jwt)")
        XCTAssertEqual(BackendError.http(404, "missing").errorDescription, "HTTP 404: missing")
        XCTAssertEqual(BackendError.decoding("oops").errorDescription, "Couldn't decode response: oops")
    }

    /// Render-then-refresh classifier: ONLY a decode failure (the API's JSON shape drifted) is a contract failure worth replacing a screen's cached content with an error. A slow/offline/timeout/HTTP-error refresh is not — it's kept and logged.
    func testIsContractFailureOnlyTrueForDecoding() {
        XCTAssertTrue(BackendError.decoding("shape drift").isContractFailure)
        XCTAssertFalse(BackendError.http(500, "server down").isContractFailure)
        XCTAssertFalse(BackendError.http(0, "no response").isContractFailure)
        XCTAssertFalse(BackendError.notAuthenticated(reason: "no jwt").isContractFailure)
        XCTAssertFalse(BackendError.invalidURL.isContractFailure)
    }

    /// The profile DTOs carry the user's name as `preferred_name` on the wire (renamed from display_name). Pin the snake_case mapping so a regression back to displayName/display_name is caught here, not as a field the backend silently drops.
    func testProfilePreferredNameUsesSnakeCaseWire() throws {
        let update = ProfileUpdate(
            preferredName: "Wes", namePronunciation: nil, nativeLanguages: nil,
            targetLanguage: nil, targetAccents: nil, proficiency: nil,
            tutorSpeakingSpeed: nil, correctionFrequency: nil, goals: nil, locationCity: nil, timezone: nil,
        )
        let json = try String(data: BackendAPI.encoder.encode(update), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("preferred_name"))
        XCTAssertFalse(json.contains("display_name"))
        // ProfileDTO has required (non-optional) fields; include them so the decode exercises preferred_name without throwing on missing keys.
        let dtoJSON =
            #"{"preferred_name": "Wes", "native_languages": [], "target_language": "English", "target_accents": [], "proficiency": "intermediate", "tutor_speaking_speed": "normal", "correction_frequency": "sometimes"}"#
        let decoded = try BackendAPI.decoder.decode(
            ProfileDTO.self,
            from: XCTUnwrap(dtoJSON.data(using: .utf8)),
        )
        XCTAssertEqual(decoded.preferredName, "Wes")
    }
}
