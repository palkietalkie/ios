@testable import PalkieTalkie
import XCTest

/// The pure OpenAI realtime event decoder: every event type maps to the right RealtimeEvent, malformed or ignored input decodes to nil, and the free-function helpers (usageDelta, surfacedError, parseToolCall) hold their contracts. No peer connection, no client state, so this is where the protocol logic is actually proven.
final class ParseRealtimeEventTests: XCTestCase {
    private func data(_ obj: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: obj)
    }

    func testSessionCreatedAndUpdatedParseToReady() throws {
        for type in ["session.created", "session.updated"] {
            guard case .ready = try parseRealtimeEvent(data(["type": type])) else {
                return XCTFail("\(type) must parse to .ready")
            }
        }
    }

    func testResponseCreatedParses() throws {
        guard case .responseCreated = try parseRealtimeEvent(data(["type": "response.created"])) else {
            return XCTFail("expected .responseCreated")
        }
    }

    func testSpeechStartedParses() throws {
        guard case .speechStarted = try parseRealtimeEvent(data(["type": "input_audio_buffer.speech_started"])) else {
            return XCTFail("expected .speechStarted")
        }
    }

    func testPersonaTranscriptDeltaCarriesText() throws {
        guard case let .personaTranscriptDelta(text) = try parseRealtimeEvent(data([
            "type": "response.output_audio_transcript.delta",
            "delta": "Hi",
        ])) else {
            return XCTFail("expected .personaTranscriptDelta")
        }
        XCTAssertEqual(text, "Hi")
    }

    func testEmptyPersonaDeltaIsDropped() throws {
        XCTAssertNil(
            try parseRealtimeEvent(data(["type": "response.output_audio_transcript.delta", "delta": ""])),
            "an empty delta is noise, not a turn",
        )
    }

    func testUserTranscriptCarriesText() throws {
        guard case let .userTranscript(text) = try parseRealtimeEvent(data([
            "type": "conversation.item.input_audio_transcription.completed",
            "transcript": "good morning",
        ])) else {
            return XCTFail("expected .userTranscript")
        }
        XCTAssertEqual(text, "good morning")
    }

    func testResponseDoneCarriesUsage() throws {
        guard case let .responseDone(usage) = try parseRealtimeEvent(data([
            "type": "response.done",
            "response": ["usage": ["input_tokens": 12, "output_tokens": 4]],
        ])) else {
            return XCTFail("expected .responseDone")
        }
        XCTAssertEqual(usage.inputTokens, 12)
        XCTAssertEqual(usage.outputTokens, 4)
    }

    func testFunctionCallCarriesToolCall() throws {
        guard case let .toolCall(call) = try parseRealtimeEvent(data([
            "type": "response.function_call_arguments.done",
            "call_id": "c1",
            "name": "search_web",
            "arguments": "{\"query\": \"weather\"}",
        ])) else {
            return XCTFail("expected .toolCall")
        }
        XCTAssertEqual(call.callId, "c1")
        XCTAssertEqual(call.name, "search_web")
        XCTAssertEqual(call.query, "weather")
    }

    func testRealErrorCarriesMessage() throws {
        guard case let .error(message) = try parseRealtimeEvent(data([
            "type": "error",
            "error": ["code": "insufficient_quota", "message": "quota exceeded"],
        ])) else {
            return XCTFail("expected .error")
        }
        XCTAssertEqual(message, "quota exceeded")
    }

    func testBenignActiveResponseErrorParsesToNilMessage() throws {
        guard case let .error(message) = try parseRealtimeEvent(data([
            "type": "error",
            "error": ["code": "conversation_already_has_active_response", "message": "active response in progress"],
        ])) else {
            return XCTFail("still an .error event, just a benign one")
        }
        XCTAssertNil(message, "benign race → nil message so dispatch drops it instead of ending the session")
    }

    func testMalformedAndIgnoredTypesParseToNil() throws {
        XCTAssertNil(parseRealtimeEvent(Data("not json".utf8)))
        XCTAssertNil(try parseRealtimeEvent(data(["no_type": 1])))
        XCTAssertNil(
            try parseRealtimeEvent(data(["type": "response.output_audio.delta"])),
            "audio deltas are ignored: WebRTC plays tutor audio via its media track, not app-decoded bytes",
        )
    }

    func testUsageDeltaZeroWhenBlockMissing() {
        XCTAssertEqual(usageDelta(from: [:]), .zero)
        XCTAssertEqual(usageDelta(from: ["response": [:]]), .zero)
    }

    func testUsageDeltaDefaultsMissingFieldToZero() {
        let delta = usageDelta(from: ["response": ["usage": ["input_tokens": 7]]])
        XCTAssertEqual(delta.inputTokens, 7)
        XCTAssertEqual(delta.outputTokens, 0)
    }

    func testSurfacedErrorDropsByCodeAndByMessage() {
        XCTAssertNil(surfacedError(from: ["error": [
            "code": "conversation_already_has_active_response",
            "message": "x",
        ]]))
        XCTAssertNil(
            surfacedError(from: ["error": ["message": "Conversation already has an active response in progress."]]),
        )
    }

    func testSurfacedErrorFallsBackToUnknown() {
        XCTAssertEqual(surfacedError(from: ["type": "error"]), "unknown error")
    }

    func testParseToolCallNilWithoutIdOrName() {
        XCTAssertNil(parseToolCall(from: ["name": "x"]), "no call_id → nil")
        XCTAssertNil(parseToolCall(from: ["call_id": "c1"]), "no name → nil")
    }

    func testParseToolCallDefaultsQueryToEmpty() {
        let call = parseToolCall(from: ["call_id": "c1", "name": "search_web"])
        XCTAssertEqual(call?.query, "", "missing arguments → empty query, not a crash")
    }

    func testLogLabelDoesNotLeakAssociatedValues() {
        XCTAssertEqual(RealtimeEvent.personaTranscriptDelta("secret text").logLabel, "transcript.delta")
        XCTAssertEqual(RealtimeEvent.error(nil).logLabel, "error(benign)")
        XCTAssertEqual(RealtimeEvent.error("boom").logLabel, "error")
    }
}
