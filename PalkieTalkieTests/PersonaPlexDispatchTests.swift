@testable import PalkieTalkie
import XCTest

/// Drives `PersonaPlexClient.dispatchFrame(_:)` directly so every branch of the binary-frame switch runs without
/// spinning up a real WebSocket. Production goes through `readLoop()` which forwards each received frame here.
final class PersonaPlexDispatchTests: XCTestCase {
    func testHandshakeFrameUnblocksWaiters() async {
        let client = PersonaPlexClient()
        // Wire streams so continuations exist before we feed frames.
        _ = await client.transcript
        _ = await client.inboundAudio
        _ = await client.errors
        _ = await client.metadata
        // Set up an awaiter, then dispatch the handshake. The awaiter should return.
        async let handshake: Void = client.waitForServerHandshake()
        await client.dispatchFrame(PersonaPlexClient.encodeHandshake(version: 1, model: 2))
        _ = await handshake
    }

    func testAudioFrameYieldsToInboundAudio() async {
        let client = PersonaPlexClient()
        let inbound = await client.inboundAudio
        await client.dispatchFrame(PersonaPlexClient.encodeAudio(Data([0xAA, 0xBB])))
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
        XCTAssertEqual(received, Data([0xAA, 0xBB]))
    }

    func testTextFrameYieldsTranscript() async {
        let client = PersonaPlexClient()
        let transcriptStream = await client.transcript
        // Frame: 0x02 + utf8 bytes.
        await client.dispatchFrame(Data([0x02]) + Data("hello world".utf8))
        let task = Task { () -> TranscriptChunk? in
            for await chunk in transcriptStream {
                return chunk
            }
            return nil
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        await client.close()
        let chunk = await task.value
        XCTAssertEqual(chunk?.text, "hello world")
        XCTAssertEqual(chunk?.speaker, .persona)
    }

    func testControlFrameIsIgnored() async {
        let client = PersonaPlexClient()
        _ = await client.transcript
        // Server-originated control frames are no-ops on the client side.
        await client.dispatchFrame(PersonaPlexClient.encodeControl(.endTurn))
        await client.close()
    }

    func testMetadataFrameYields() async {
        let client = PersonaPlexClient()
        let metadataStream = await client.metadata
        let payload = Data(#"{"voice_id":"NATM1"}"#.utf8)
        await client.dispatchFrame(Data([0x04]) + payload)
        let task = Task { () -> Data? in
            for await chunk in metadataStream {
                return chunk
            }
            return nil
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        await client.close()
        let value = await task.value
        XCTAssertEqual(value, payload)
    }

    func testErrorFrameYields() async {
        let client = PersonaPlexClient()
        let errorStream = await client.errors
        await client.dispatchFrame(Data([0x05]) + Data("server crashed".utf8))
        let task = Task { () -> String? in
            for await msg in errorStream {
                return msg
            }
            return nil
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        await client.close()
        let value = await task.value
        XCTAssertEqual(value, "server crashed")
    }

    func testPingFrameDispatched() async {
        let client = PersonaPlexClient()
        _ = await client.metadata
        // No transport is connected so the pong attempt is a no-op; we're just covering the dispatch branch.
        await client.dispatchFrame(PersonaPlexClient.encodePing())
        await client.close()
    }

    func testUndecodableFrameDoesNothing() async {
        let client = PersonaPlexClient()
        _ = await client.transcript
        // Frame type 0xFF isn't in FrameType — dispatchFrame returns silently.
        await client.dispatchFrame(Data([0xFF, 0x00]))
        await client.close()
    }
}
