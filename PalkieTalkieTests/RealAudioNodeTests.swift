@preconcurrency import AVFoundation
@testable import PalkieTalkie
import XCTest

/// Thin-wrapper coverage for RealAudioEngine / RealInputNode / RealMixerNode / RealAudioPlayerNode — each is a pass-through over AVAudioEngine that AudioStreamer needs in production. The fake-engine tests exercise the AudioStreamer logic; these touch the real wrappers so the getters/setters don't sit at 0% coverage.
///
/// AVAudioEngine on simulator can be allocated and inspected, but `start()` requires a valid input format which the simulator's audio session may not have. So we exercise allocation + getter/setter chains only — the start path is reachable from device tests + real-app launches.
final class RealAudioNodeTests: XCTestCase {
    func testRealAudioEngineWrapsAVAudioEngine() {
        let engine = RealAudioEngine()
        // Touch each pass-through getter to drive cover.
        _ = engine.inputNode
        _ = engine.mainMixerNode
        _ = engine.isRunning
        // prepare/stop are safe-when-not-running.
        engine.prepare()
        engine.stop()
    }

    func testAttachAndConnectPlayerNode() {
        let engine = RealAudioEngine()
        let player = RealAudioPlayerNode()
        engine.attach(player)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000,
            channels: 1,
            interleaved: false,
        ) else {
            XCTFail("format alloc failed")
            return
        }
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func testRealAudioPlayerNodeGettersSetters() {
        let player = RealAudioPlayerNode()
        player.volume = 0.5
        XCTAssertEqual(player.volume, 0.5, accuracy: 0.001)
        XCTAssertFalse(player.isPlaying, "not started")
        XCTAssertNotNil(player.underlyingPlayerNode)
        // stop() is safe before play() — no-op.
        player.stop()
    }

    func testRealMixerNodeOutputVolumeRoundTrip() {
        let mixer = RealMixerNode(node: AVAudioMixerNode())
        mixer.outputVolume = 0.7
        XCTAssertEqual(mixer.outputVolume, 0.7, accuracy: 0.001)
    }

    func testRealInputNodeAGCFlagRoundTrip() {
        let engine = AVAudioEngine()
        let input = RealInputNode(node: engine.inputNode)
        // Toggling AGC requires voice-processing enabled first; do that and round-trip the AGC flag.
        // On simulator setVoiceProcessingEnabled may throw — wrap in try? so the test still drives the getter.
        try? input.setVoiceProcessingEnabled(true)
        input.isVoiceProcessingAGCEnabled = false
        _ = input.isVoiceProcessingAGCEnabled
        try? input.setVoiceProcessingEnabled(false)
    }
}
