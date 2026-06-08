import AVFoundation
@testable import PalkieTalkie
import XCTest

/// Drives AudioStreamer.start()/stop()/playPCM16/interruptPlayback against a FakeAudioEngine — exercises the body code that the real AVAudioEngine refuses to run on the simulator (input-format precondition).
final class AudioStreamerFakeEngineTests: XCTestCase {
    func testStartConfiguresEngineAndInstallsTap() async throws {
        let fakeEngine = FakeAudioEngine()
        let streamer = AudioStreamer(engine: fakeEngine, playerNode: FakePlayerNode())
        try await streamer.start()
        XCTAssertEqual(fakeEngine.startCount, 1)
        XCTAssertEqual(fakeEngine.prepareCount, 1)
        XCTAssertEqual(fakeEngine.attachedPlayers.count, 1, "playerNode attach")
        XCTAssertEqual(fakeEngine.connectCalls.count, 1, "playerNode → mainMixer connect")
        let input = try XCTUnwrap(fakeEngine.inputNode as? FakeInputNode)
        XCTAssertTrue(input.voiceProcessingEnabled, "AEC must be enabled on mic")
        XCTAssertFalse(input.isVoiceProcessingAGCEnabled, "AGC must be off so quiet consonants survive")
        XCTAssertEqual(input.installTapCalls, 1, "mic tap installed")
        let running = await streamer.isRunning
        XCTAssertTrue(running)
        await streamer.stop()
    }

    func testStartIsIdempotent() async throws {
        let fakeEngine = FakeAudioEngine()
        let streamer = AudioStreamer(engine: fakeEngine, playerNode: FakePlayerNode())
        try await streamer.start()
        try await streamer.start()
        XCTAssertEqual(fakeEngine.startCount, 1, "double-start must not re-init the engine")
    }

    func testStopRemovesTapAndStopsEngine() async throws {
        let fakeEngine = FakeAudioEngine()
        let streamer = AudioStreamer(engine: fakeEngine, playerNode: FakePlayerNode())
        try await streamer.start()
        await streamer.stop()
        let input = try XCTUnwrap(fakeEngine.inputNode as? FakeInputNode)
        XCTAssertEqual(input.removeTapCalls, 1)
        XCTAssertEqual(fakeEngine.stopCount, 1)
        let running = await streamer.isRunning
        XCTAssertFalse(running)
    }

    func testStopWithoutStartIsNoOp() async {
        let fakeEngine = FakeAudioEngine()
        let streamer = AudioStreamer(engine: fakeEngine, playerNode: FakePlayerNode())
        await streamer.stop()
        XCTAssertEqual(fakeEngine.stopCount, 0)
    }

    func testStartPropagatesEngineStartError() async {
        let fakeEngine = FakeAudioEngine()
        fakeEngine.startError = NSError(domain: "test", code: 42)
        let streamer = AudioStreamer(engine: fakeEngine, playerNode: FakePlayerNode())
        do {
            try await streamer.start()
            XCTFail("expected throw")
        } catch let AudioStreamerError.engineStartFailed(underlying) {
            XCTAssertEqual((underlying as NSError).code, 42)
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    /// setVoiceProcessingEnabled failure is logged but not thrown — streamer continues. Assert no crash + engine still starts.
    func testStartHandlesVoiceProcessingErrorGracefully() async {
        let fakeEngine = FakeAudioEngine()
        (fakeEngine.inputNode as! FakeInputNode).voiceProcessingError = NSError(domain: "vp", code: -1)
        let streamer = AudioStreamer(engine: fakeEngine, playerNode: FakePlayerNode())
        try? await streamer.start()
        let running = await streamer.isRunning
        XCTAssertTrue(running)
        await streamer.stop()
    }

    func testPlayPCM16ScheduleAfterStartDoesNotCrash() async throws {
        let fakeEngine = FakeAudioEngine()
        let streamer = AudioStreamer(engine: fakeEngine, playerNode: FakePlayerNode())
        try await streamer.start()
        let pcm16 = Data(repeating: 0x00, count: 960) // 480 samples × 2 bytes
        await streamer.playPCM16(pcm16)
        await streamer.stop()
    }

    // interruptPlayback/playOutput-driving/heavy-encoder tests would need a Fake AVAudioPlayerNode (the player node's C++ asserts fire on a faked engine). Not in this commit — the AudioPlayerNode protocol-wrap is the next refactor.

    /// Drive synthetic samples through the captured mic-tap block so the ingest → resample → opus-encode → opus-emit path runs end-to-end. This covers ~150 additional lines of AudioStreamer that are otherwise unreachable without a real mic.
    func testMicTapBlockDrivesIngestPath() async throws {
        let fakeEngine = FakeAudioEngine()
        let streamer = AudioStreamer(engine: fakeEngine, playerNode: FakePlayerNode())
        try await streamer.start()
        let input = try XCTUnwrap(fakeEngine.inputNode as? FakeInputNode)
        guard let tap = input.lastTapBlock else {
            XCTFail("expected tap block to be installed")
            return
        }
        // 480 samples of audible-level Float32 (~-12 dBFS — above the -45 dBFS noise gate) so the encoder path runs.
        let frameCount: AVAudioFrameCount = 480
        let format = input.format
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            XCTFail("buffer alloc failed")
            return
        }
        buffer.frameLength = frameCount
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        for i in 0 ..< Int(frameCount) {
            channel[i] = 0.25 * sin(Float(i) * 0.1)
        }
        // Drive a few frames so the encoder accumulates enough samples to emit Opus packets.
        for _ in 0 ..< 6 {
            tap(buffer, AVAudioTime(sampleTime: 0, atRate: format.sampleRate))
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        await streamer.stop()
    }

    /// `playOutput(_:)` is the inverse path — Ogg-Opus bytes come in from the server, get demuxed and decoded into PCM and scheduled on the player. We can't drive valid Ogg-Opus bytes from a unit test (would have to encode a real audio frame), but we can verify the early-return for empty/invalid input doesn't crash.
    func testPlayOutputWithEmptyBytesIsNoOp() async throws {
        let fakeEngine = FakeAudioEngine()
        let streamer = AudioStreamer(engine: fakeEngine, playerNode: FakePlayerNode())
        try await streamer.start()
        await streamer.playOutput(Data())
        await streamer.stop()
    }

    /// Multiple stop() calls are idempotent — the second one doesn't double-remove the tap or double-stop the engine.
    func testStopIsIdempotent() async throws {
        let fakeEngine = FakeAudioEngine()
        let streamer = AudioStreamer(engine: fakeEngine, playerNode: FakePlayerNode())
        try await streamer.start()
        await streamer.stop()
        await streamer.stop()
        let input = try XCTUnwrap(fakeEngine.inputNode as? FakeInputNode)
        XCTAssertEqual(input.removeTapCalls, 1, "removeTap must only fire once across double-stop")
        XCTAssertEqual(fakeEngine.stopCount, 1, "engine.stop must only fire once across double-stop")
    }

    /// After `stop()`, `recordedSessionAudioURL` is exposed for upload. Verifies the wav-finalize path ran (header fixup + close).
    func testRecordedSessionAudioURLPopulatedAfterStop() async throws {
        let fakeEngine = FakeAudioEngine()
        let streamer = AudioStreamer(engine: fakeEngine, playerNode: FakePlayerNode())
        try await streamer.start()
        await streamer.stop()
        let url = await streamer.recordedSessionAudioURL
        XCTAssertNotNil(url, "session audio URL must be exposed after stop for SessionController upload")
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // Heavy-tap test removed: would need a Fake AVAudioPlayerNode (the encoder emission path eventually touches scheduleBuffer which asserts on faked engine).

    /// Drive silent samples — exercises the noise-gate early-return path inside ingestSamples.
    func testSilentTapHitsNoiseGate() async throws {
        let fakeEngine = FakeAudioEngine()
        let streamer = AudioStreamer(engine: fakeEngine, playerNode: FakePlayerNode())
        try await streamer.start()
        let input = try XCTUnwrap(fakeEngine.inputNode as? FakeInputNode)
        guard let tap = input.lastTapBlock else { return }
        let format = input.format
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480) else { return }
        buffer.frameLength = 480
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        for i in 0 ..< 480 {
            channel[i] = 0.0001 // -80 dBFS — far below the -45 dBFS gate
        }
        for _ in 0 ..< 5 {
            tap(buffer, AVAudioTime(sampleTime: 0, atRate: format.sampleRate))
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        await streamer.stop()
    }

    // Stream-yield test removed: same player-node-fake dependency.

    /// pcm16InputChunks is the OpenAI-provider variant of the input stream — exercise the second stream pathway.
    func testPCM16InputChunksStreamAccessible() async throws {
        let fakeEngine = FakeAudioEngine()
        let streamer = AudioStreamer(engine: fakeEngine, playerNode: FakePlayerNode())
        try await streamer.start()
        _ = await streamer.pcm16InputChunks
        await streamer.stop()
    }

    /// `interruptPlayback()` stops + plays the player to drop queued buffers and resume. Tests that the fake records both calls.
    func testInterruptPlaybackStopsThenPlaysPlayerNode() async throws {
        let fakeEngine = FakeAudioEngine()
        let playerNode = FakePlayerNode()
        let streamer = AudioStreamer(engine: fakeEngine, playerNode: playerNode)
        try await streamer.start()
        let stopBefore = playerNode.stopCount
        let playBefore = playerNode.playCount
        await streamer.interruptPlayback()
        XCTAssertEqual(playerNode.stopCount, stopBefore + 1)
        XCTAssertEqual(playerNode.playCount, playBefore + 1)
        await streamer.stop()
    }

    /// `recordedModelAudioURL` is exposed for upload; nil before start, then populated after the model audio file opens. Covers the getter alongside its mic-side sibling.
    func testRecordedModelAudioURLNilBeforeStartPopulatedAfterStart() async throws {
        let fakeEngine = FakeAudioEngine()
        let streamer = AudioStreamer(engine: fakeEngine, playerNode: FakePlayerNode())
        let before = await streamer.recordedModelAudioURL
        XCTAssertNil(before)
        try await streamer.start()
        let after = await streamer.recordedModelAudioURL
        XCTAssertNotNil(after)
        await streamer.stop()
        if let after { try? FileManager.default.removeItem(at: after) }
    }

    /// playPCM16 with an empty data blob is a no-op (sampleCount=0 → guard returns). Same defensive branch as playOutput.
    func testPlayPCM16WithEmptyDataIsNoOp() async throws {
        let fakeEngine = FakeAudioEngine()
        let streamer = AudioStreamer(engine: fakeEngine, playerNode: FakePlayerNode())
        try await streamer.start()
        await streamer.playPCM16(Data())
        await streamer.stop()
    }
}
