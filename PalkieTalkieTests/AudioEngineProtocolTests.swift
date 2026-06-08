@preconcurrency import AVFoundation
@testable import PalkieTalkie
import XCTest

/// Pure-construction smoke tests for the protocol seam types in `AudioEngineProtocol.swift`. The deeper behavior is covered by `AudioStreamerFakeEngineTests` and `RealAudioNodeTests` — this file exists to pair-match the source file name so the CI test-pair check accepts the protocol-seam extraction.
final class AudioEngineProtocolTests: XCTestCase {
    func testRealAudioEngineConstructsAndExposesProtocolSurface() {
        let engine: AudioEngineProtocol = RealAudioEngine()
        // Touching the protocol getters confirms RealAudioEngine satisfies the contract without needing the engine to start.
        _ = engine.inputNode
        _ = engine.mainMixerNode
        XCTAssertFalse(engine.isRunning, "fresh engine must not report running")
    }

    func testRealAudioPlayerNodeConstructsAndExposesProtocolSurface() {
        let player: AudioPlayerNodeProtocol = RealAudioPlayerNode()
        // volume + isPlaying are part of the protocol the streamer reads.
        XCTAssertEqual(player.volume, 1.0, accuracy: 0.001, "default volume should be unity")
        XCTAssertFalse(player.isPlaying)
        // Round-trip the underlyingPlayerNode escape hatch the protocol exposes for AVAudioEngine.scheduleBuffer paths.
        XCTAssertNotNil(player.underlyingPlayerNode)
    }
}
