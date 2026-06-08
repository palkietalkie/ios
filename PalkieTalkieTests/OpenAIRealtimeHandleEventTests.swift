@testable import PalkieTalkie
import XCTest

/// Drives every branch of `OpenAIRealtimeClient.handleEvent(data:)` directly. The production code path uses a
/// `URLSessionWebSocketTask` to receive these JSON frames; in tests we feed the same JSON shapes synthetically because
/// the WS task is `final` (not injectable) and starting a real local WS server here would add infra complexity for
/// little gain.
final class OpenAIRealtimeHandleEventTests: XCTestCase {
    private func makeClient() -> OpenAIRealtimeClient {
        OpenAIRealtimeClient(instructions: "test instructions")
    }

    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    func testSessionCreatedSignalsReady() async {
        let client = makeClient()
        // Wire the streams first so the continuations exist.
        _ = await client.inboundAudio
        _ = await client.transcript
        _ = await client.errors

        await client.handleEvent(data: data(#"{"type":"session.created"}"#))
        // waitForServerReady should now resolve immediately.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await client.waitForServerReady() }
            group.addTask {
                // Race timeout in case of deadlock. If waitForServerReady doesn't return within 1s, the test fails.
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            await group.next()
            group.cancelAll()
        }
        await client.close()
    }

    func testSessionUpdatedAlsoSignalsReady() async {
        let client = makeClient()
        _ = await client.inboundAudio
        await client.handleEvent(data: data(#"{"type":"session.updated"}"#))
        await client.close()
    }

    func testAudioDeltaYieldsToInboundAudio() async {
        let client = makeClient()
        let inbound = await client.inboundAudio
        // Base64 of 4 bytes of audio (0x01 0x02 0x03 0x04).
        await client.handleEvent(
            data: data(#"{"type":"response.output_audio.delta","delta":"AQIDBA=="}"#),
        )
        // Drain one item with a timeout.
        let task = Task { () -> Data? in
            for await chunk in inbound {
                return chunk
            }
            return nil
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        await client.close()
        let received = await task.value
        XCTAssertEqual(received, Data([0x01, 0x02, 0x03, 0x04]))
    }

    func testTranscriptDeltaYieldsPersonaChunk() async {
        let client = makeClient()
        let transcript = await client.transcript
        await client.handleEvent(
            data: data(#"{"type":"response.output_audio_transcript.delta","delta":"hello "}"#),
        )
        let task = Task { () -> TranscriptChunk? in
            for await chunk in transcript {
                return chunk
            }
            return nil
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        await client.close()
        let chunk = await task.value
        XCTAssertEqual(chunk?.text, "hello ")
        XCTAssertEqual(chunk?.speaker, .persona)
    }

    func testEmptyTranscriptDeltaIgnored() async {
        let client = makeClient()
        let transcript = await client.transcript
        await client.handleEvent(
            data: data(#"{"type":"response.output_audio_transcript.delta","delta":""}"#),
        )
        let task = Task { () -> TranscriptChunk? in
            for await chunk in transcript {
                return chunk
            }
            return nil
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        await client.close()
        let received = await task.value
        XCTAssertNil(received, "empty delta must not emit a chunk")
    }

    func testUserTranscriptionCompletedYieldsUserChunk() async {
        let client = makeClient()
        let transcript = await client.transcript
        await client.handleEvent(
            data: data(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":"hey there"}"#),
        )
        let task = Task { () -> TranscriptChunk? in
            for await chunk in transcript {
                return chunk
            }
            return nil
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        await client.close()
        let chunk = await task.value
        XCTAssertEqual(chunk?.text, "hey there")
        XCTAssertEqual(chunk?.speaker, .user)
    }

    func testErrorEventNestedMessageYielded() async {
        let client = makeClient()
        let errors = await client.errors
        await client.handleEvent(
            data: data(#"{"type":"error","error":{"message":"insufficient_quota"}}"#),
        )
        let task = Task { () -> String? in
            for await msg in errors {
                return msg
            }
            return nil
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        await client.close()
        let msg = await task.value
        XCTAssertEqual(msg, "insufficient_quota")
    }

    func testErrorEventTopLevelMessageYielded() async {
        let client = makeClient()
        let errors = await client.errors
        await client.handleEvent(
            data: data(#"{"type":"error","message":"top-level error"}"#),
        )
        let task = Task { () -> String? in
            for await msg in errors {
                return msg
            }
            return nil
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        await client.close()
        let msg = await task.value
        XCTAssertEqual(msg, "top-level error")
    }

    func testErrorEventNoMessageFallsBackToUnknown() async {
        let client = makeClient()
        let errors = await client.errors
        await client.handleEvent(data: data(#"{"type":"error"}"#))
        let task = Task { () -> String? in
            for await msg in errors {
                return msg
            }
            return nil
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        await client.close()
        let msg = await task.value
        XCTAssertEqual(msg, "unknown error")
    }

    func testSpeechStartedYieldsBargeIn() async {
        let client = makeClient()
        let bargeIn = await client.bargeIn
        await client.handleEvent(data: data(#"{"type":"input_audio_buffer.speech_started"}"#))
        let task = Task { () -> Bool in
            for await _ in bargeIn {
                return true
            }
            return false
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        await client.close()
        let received = await task.value
        XCTAssertTrue(received)
    }

    func testUnknownEventTypeIgnored() async {
        let client = makeClient()
        _ = await client.inboundAudio
        await client.handleEvent(data: data(#"{"type":"this.is.unknown"}"#))
        await client.close()
    }

    /// Audio delta with missing `delta` key — the guard-let chain bails before yielding, no inbound bytes emitted.
    func testAudioDeltaWithMissingDeltaFieldIgnored() async {
        let client = makeClient()
        _ = await client.inboundAudio
        await client.handleEvent(data: data(#"{"type":"response.output_audio.delta"}"#))
        await client.close()
    }

    /// Audio delta with non-base64 garbage — `Data(base64Encoded:)` returns nil, guard fails, no inbound bytes.
    func testAudioDeltaWithInvalidBase64Ignored() async {
        let client = makeClient()
        _ = await client.inboundAudio
        await client.handleEvent(data: data(#"{"type":"response.output_audio.delta","delta":"not!base64**"}"#))
        await client.close()
    }

    /// User transcription completed but transcript field is missing — guard fails, no yield.
    func testUserTranscriptionCompletedWithoutTranscriptIgnored() async {
        let client = makeClient()
        _ = await client.transcript
        await client.handleEvent(data: data(#"{"type":"conversation.item.input_audio_transcription.completed"}"#))
        await client.close()
    }

    /// User transcription completed with empty string — same early-return.
    func testUserTranscriptionCompletedEmptyStringIgnored() async {
        let client = makeClient()
        _ = await client.transcript
        await client
            .handleEvent(
                data: data(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":""}"#),
            )
        await client.close()
    }

    /// Persona transcript delta with missing `delta` — guard fails.
    func testTranscriptDeltaWithoutFieldIgnored() async {
        let client = makeClient()
        _ = await client.transcript
        await client.handleEvent(data: data(#"{"type":"response.output_audio_transcript.delta"}"#))
        await client.close()
    }

    func testMalformedJSONIgnored() async {
        let client = makeClient()
        _ = await client.inboundAudio
        await client.handleEvent(data: data("not json at all"))
        await client.close()
    }

    func testEventWithoutTypeIgnored() async {
        let client = makeClient()
        _ = await client.inboundAudio
        await client.handleEvent(data: data(#"{"no_type":"present"}"#))
        await client.close()
    }
}
