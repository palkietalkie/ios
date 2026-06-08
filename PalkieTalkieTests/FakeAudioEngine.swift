@preconcurrency import AVFoundation
import Foundation
@testable import PalkieTalkie

/// Test double for AudioEngineProtocol. Produces a valid record-capable input format so AudioStreamer's `setVoiceProcessingEnabled` + `installTap` paths don't hit AVAudioEngine's C++ assertion on the simulator. Records every method call so tests can assert lifecycle ordering.
final class FakeAudioEngine: AudioEngineProtocol, @unchecked Sendable {
    let inputNode: AudioInputNodeProtocol
    let mainMixerNode: AudioMixerNodeProtocol
    private(set) var isRunning = false

    var attachedPlayers: [AudioPlayerNodeProtocol] = []
    var connectCalls: [(AudioPlayerNodeProtocol, AVAudioFormat)] = []
    var prepareCount = 0
    var startCount = 0
    var stopCount = 0
    /// When set, `start()` throws this instead of succeeding.
    var startError: Error?

    init(inputNode: FakeInputNode = FakeInputNode(), mainMixer: FakeMixerNode = FakeMixerNode()) {
        self.inputNode = inputNode
        mainMixerNode = mainMixer
    }

    func attach(_ player: AudioPlayerNodeProtocol) {
        attachedPlayers.append(player)
    }

    func connect(_ player: AudioPlayerNodeProtocol, to _: AudioMixerNodeProtocol, format: AVAudioFormat) {
        connectCalls.append((player, format))
    }

    func prepare() {
        prepareCount += 1
    }

    func start() throws {
        if let startError { throw startError }
        startCount += 1
        isRunning = true
    }

    func stop() {
        stopCount += 1
        isRunning = false
    }
}

final class FakeInputNode: AudioInputNodeProtocol, @unchecked Sendable {
    /// Returned by `inputFormat(forBus:)`. Default is a valid 24kHz mono Float32 format so tap installation doesn't crash.
    var format: AVAudioFormat
    var voiceProcessingEnabled = false
    var isVoiceProcessingAGCEnabled = false
    var voiceProcessingError: Error?
    var installTapCalls = 0
    var removeTapCalls = 0
    var lastTapBlock: AVAudioNodeTapBlock?

    init(format: AVAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24000,
        channels: 1,
        interleaved: false,
    )!) {
        self.format = format
    }

    func inputFormat(forBus _: AVAudioNodeBus) -> AVAudioFormat {
        format
    }

    func setVoiceProcessingEnabled(_ enabled: Bool) throws {
        if let voiceProcessingError { throw voiceProcessingError }
        voiceProcessingEnabled = enabled
    }

    func installTap(
        onBus _: AVAudioNodeBus,
        bufferSize _: AVAudioFrameCount,
        format _: AVAudioFormat?,
        block: @escaping AVAudioNodeTapBlock,
    ) {
        installTapCalls += 1
        lastTapBlock = block
    }

    func removeTap(onBus _: AVAudioNodeBus) {
        removeTapCalls += 1
    }
}

final class FakeMixerNode: AudioMixerNodeProtocol, @unchecked Sendable {
    var outputVolume: Float = 1.0
}

final class FakePlayerNode: AudioPlayerNodeProtocol, @unchecked Sendable {
    var volume: Float = 1.0
    private(set) var isPlaying: Bool = false
    var playCount = 0
    var stopCount = 0
    var scheduledBuffers: [AVAudioPCMBuffer] = []

    func play() {
        playCount += 1
        isPlaying = true
    }

    func stop() {
        stopCount += 1
        isPlaying = false
    }

    func scheduleBuffer(_ buffer: AVAudioPCMBuffer, completionHandler _: AVAudioNodeCompletionHandler?) {
        scheduledBuffers.append(buffer)
    }

    /// Fakes return nil so the real-engine wrapper's attach/connect become no-ops with this player.
    var underlyingPlayerNode: AVAudioPlayerNode? {
        nil
    }
}
