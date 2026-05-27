@testable import PalkieTalkie
import XCTest

// Regression test for the "audio sent before server handshake" bug.
//
// Background: the server's recv_loop only starts after `step_system_prompts_async` (15-30s on cold start). The protocol
// signals "I'm ready, send audio" via a one-byte `\x00` handshake frame from server to client. If the client (iOS)
// starts the audio pump immediately on WS-open, audio bytes either queue up out of order or get dropped — the server's
// Ogg-Opus decoder then sees mid-stream audio pages with no preceding OpusHead, dies, and the whole session collapses
// with `sphn ValueError: sending on a closed channel`.
//
// The contract being locked in here: `AudioPump.start` MUST NOT call `session.send(audio:)` until
// `session.waitForServerReady()` resolves. If a regression silently removes the await, this test pins it down.

@MainActor
final class AudioPumpTests: XCTestCase {
    func test_pump_waits_for_server_handshake_before_sending_audio() async throws {
        let session = HandshakeGatedSession()
        let streamer = ReplayStreamer(frames: [Data([0xAA]), Data([0xBB])])

        let pump = AudioPump()
        await pump.start(streamer: streamer, session: session)

        // Give the detached task a moment to run. It MUST be parked on waitForServerReady.
        try await Task.sleep(for: .milliseconds(150))
        let beforeHandshake = await session.recordedAudio
        XCTAssertEqual(beforeHandshake, [], "pump must not send any audio frame before server handshake")

        // Now release the handshake gate. Pump should drain the streamer.
        await session.signalReady()
        try await Task.sleep(for: .milliseconds(150))
        let afterHandshake = await session.recordedAudio
        XCTAssertEqual(
            afterHandshake,
            [Data([0xAA]), Data([0xBB])],
            "pump should forward all queued frames once handshake signaled"
        )

        await pump.stop()
    }
}

// MARK: - Fixtures

/// A `PersonaPlexSessionType` that holds `waitForServerReady` open until `signalReady` is called, and records every
/// audio frame the pump tries to send.
private actor HandshakeGatedSession: PersonaPlexSessionType {
    var recordedAudio: [Data] = []

    private var handshakeFired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private let (audioStream, audioCont) = AsyncStream.makeStream(of: Data.self)
    private let (transcriptStream, transcriptCont) = AsyncStream.makeStream(of: TranscriptChunk.self)
    private let (errorStream, errorCont) = AsyncStream.makeStream(of: String.self)

    func open(wsUrl _: String) async throws {}
    func open(wsUrl _: String, ephemeralToken _: String?) async throws {}
    func close() async {
        audioCont.finish()
        transcriptCont.finish()
        errorCont.finish()
    }

    func send(control _: PersonaPlexClient.ControlAction) async throws {}

    func send(audio opusFrame: Data) async throws {
        recordedAudio.append(opusFrame)
    }

    func waitForServerReady() async {
        if handshakeFired { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            waiters.append(c)
        }
    }

    /// Test hook to release the handshake gate.
    func signalReady() {
        handshakeFired = true
        let resumers = waiters
        waiters.removeAll()
        for r in resumers {
            r.resume()
        }
    }

    nonisolated var inboundAudio: AsyncStream<Data> {
        get async { audioStream }
    }

    nonisolated var transcript: AsyncStream<TranscriptChunk> {
        get async { transcriptStream }
    }

    nonisolated var errors: AsyncStream<String> {
        get async { errorStream }
    }
}

/// Streamer that yields a fixed list of frames then finishes.
private final class ReplayStreamer: AudioStreamerType, @unchecked Sendable {
    private let stream: AsyncStream<Data>

    init(frames: [Data]) {
        stream = AsyncStream<Data> { continuation in
            for f in frames {
                continuation.yield(f)
            }
            continuation.finish()
        }
    }

    var inputChunks: AsyncStream<Data> {
        get async { stream }
    }

    func playOutput(_: Data) async {}
}
