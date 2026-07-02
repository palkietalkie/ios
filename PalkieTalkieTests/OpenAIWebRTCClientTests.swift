@testable import PalkieTalkie
import XCTest

/// The OpenAI WebRTC client's runtime behavior: the response lifecycle guard, transient-retry classification, inbound-audio-level extraction, the control-message API, and handleEvent's dispatch of decoded events onto the client's streams. The protocol DECODING is tested directly in ParseRealtimeEventTests; the SDP handshake + WebRTC delegates need a real peer connection and are exercised on-device.
final class OpenAIWebRTCClientTests: XCTestCase {
    func testInboundAudioLevelReadsTheInboundAudioTrack() {
        // Waveform source on WebRTC: the tutor's amplitude is the inbound-rtp AUDIO subreport's audioLevel — not our outbound mic, not a video track.
        let stats: [(type: String, values: [String: Any])] = [
            ("outbound-rtp", ["kind": "audio", "audioLevel": NSNumber(value: 0.9)]),
            ("inbound-rtp", ["kind": "video", "audioLevel": NSNumber(value: 0.1)]),
            ("inbound-rtp", ["kind": "audio", "audioLevel": NSNumber(value: 0.5)]),
        ]
        XCTAssertEqual(OpenAIWebRTCClient.inboundAudioLevel(fromStats: stats), 0.5, accuracy: 0.0001)
    }

    func testInboundAudioLevelZeroWhenAbsent() {
        XCTAssertEqual(OpenAIWebRTCClient.inboundAudioLevel(fromStats: []), 0, "no stats yet (pre-connection) → 0")
        XCTAssertEqual(
            OpenAIWebRTCClient.inboundAudioLevel(fromStats: [("inbound-rtp", ["kind": "audio"])]),
            0, "audioLevel field missing → 0",
        )
    }

    // MARK: handleEvent (data-channel event dispatch)

    // handleEvent parses the same OpenAI realtime JSON events the WS path did (transcript, barge-in, usage, tool calls, errors); it's the bulk of the client's non-hardware logic. Exercised on a fresh instance: the async streams capture what each event yields, and sends are no-ops without a data channel. The SDP handshake + WebRTC delegates need a live peer connection and stay on-device.

    private func event(_ obj: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: obj)
    }

    func testSessionCreatedMarksReady() async throws {
        let client = OpenAIWebRTCClient()
        try client.handleEvent(event(["type": "session.created"]))
        await client.waitForServerReady() // markReady flipped isReady, so this must return instead of hanging
    }

    func testPersonaTranscriptDeltaYields() async throws {
        let client = OpenAIWebRTCClient()
        let stream = await client.transcript
        try client.handleEvent(event(["type": "response.output_audio_transcript.delta", "delta": "Hello there"]))
        var got: TranscriptChunk?
        for await chunk in stream {
            got = chunk; break
        }
        XCTAssertEqual(got?.speaker, .persona)
        XCTAssertEqual(got?.text, "Hello there")
    }

    func testUserTranscriptCompletionYields() async throws {
        let client = OpenAIWebRTCClient()
        let stream = await client.transcript
        try client.handleEvent(event([
            "type": "conversation.item.input_audio_transcription.completed",
            "transcript": "good morning",
        ]))
        var got: TranscriptChunk?
        for await chunk in stream {
            got = chunk; break
        }
        XCTAssertEqual(got?.speaker, .user)
        XCTAssertEqual(got?.text, "good morning")
    }

    func testSpeechStartedYieldsBargeIn() async throws {
        let client = OpenAIWebRTCClient()
        let stream = await client.bargeIn
        try client.handleEvent(event(["type": "input_audio_buffer.speech_started"]))
        var fired = false
        for await _ in stream {
            fired = true; break
        }
        XCTAssertTrue(fired, "speech_started must yield barge-in so queued tutor audio is interrupted")
    }

    func testResponseDoneAccumulatesUsageAcrossTurns() async throws {
        let client = OpenAIWebRTCClient()
        try client.handleEvent(event([
            "type": "response.done",
            "response": ["usage": ["input_tokens": 10, "output_tokens": 5]],
        ]))
        try client.handleEvent(event([
            "type": "response.done",
            "response": ["usage": ["input_tokens": 3, "output_tokens": 2]],
        ]))
        let usage = await client.usage
        XCTAssertEqual(usage.inputTokens, 13, "token usage sums across response.done events")
        XCTAssertEqual(usage.outputTokens, 7)
    }

    func testRealErrorEventYieldsMessage() async throws {
        let client = OpenAIWebRTCClient()
        let stream = await client.errors
        try client.handleEvent(event([
            "type": "error",
            "error": ["code": "insufficient_quota", "message": "You exceeded your current quota."],
        ]))
        var got: String?
        for await message in stream {
            got = message; break
        }
        XCTAssertEqual(got, "You exceeded your current quota.")
    }

    func testFunctionCallEventYieldsToolCall() async throws {
        let client = OpenAIWebRTCClient()
        let stream = await client.toolCalls
        try client.handleEvent(event([
            "type": "response.function_call_arguments.done",
            "call_id": "call_1", "name": "search_web", "arguments": "{\"query\": \"weather in SF\"}",
        ]))
        var got: ToolCall?
        for await call in stream {
            got = call; break
        }
        XCTAssertEqual(got?.callId, "call_1")
        XCTAssertEqual(got?.name, "search_web")
        XCTAssertEqual(got?.query, "weather in SF")
    }

    func testMalformedEventIsIgnored() {
        let client = OpenAIWebRTCClient()
        client.handleEvent(Data("not json".utf8)) // non-JSON → dropped, no crash
        client.handleEvent(Data("{\"no_type\":1}".utf8)) // missing "type" → dropped
    }

    func testCloseIsSafeWithoutPeerConnection() async {
        let client = OpenAIWebRTCClient()
        await client.close() // teardown before any handshake must not crash on nil peer/channel
    }

    func testOpenRejectsMissingEphemeralToken() async {
        let client = OpenAIWebRTCClient()
        do {
            try await client.open(wsUrl: "https://api.openai.com/v1/realtime/calls?model=x", ephemeralToken: nil)
            XCTFail("WebRTC needs the ephemeral token; open must reject before any network or peer setup")
        } catch {
            XCTAssertTrue(
                error is OpenAIWebRTCError,
                "a missing token is an OpenAIWebRTCError, not some downstream failure",
            )
        }
    }

    func testSendAudioIsNoOp() async throws {
        // WebRTC carries mic audio as a media track, not app-pushed bytes — send(audio:) must be a harmless no-op (AudioPump is bypassed for this provider).
        let client = OpenAIWebRTCClient()
        try await client.send(audio: Data([1, 2, 3]))
    }

    func testInjectSystemHintRunsWithoutChannel() async {
        // Free-cap wind-down: with no reply in flight it fires the goodbye immediately (the send no-ops without a data channel, but the wind-down decision + item construction execute).
        let client = OpenAIWebRTCClient()
        await client.injectSystemHint("Let's start wrapping up.")
    }

    func testSubmitToolOutputRunsWithoutChannel() async {
        // Tool-output submission: exercises the function_call_output construction + the follow-up response.create (sends no-op without a channel).
        let client = OpenAIWebRTCClient()
        await client.submitToolOutput(callId: "call_1", output: "sunny, 72F")
    }
}
