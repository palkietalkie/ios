@preconcurrency import AVFoundation
import Foundation

/// Seam over AVAudioEngine. Production uses `RealAudioEngine` (wraps AVAudioEngine 1:1). Tests use a Fake that fakes the input format + start/stop transitions so AudioStreamer's body code can run under XCTest without AVAudioEngine's C++ assertion firing on the simulator.
protocol AudioEngineProtocol: AnyObject {
    var inputNode: AudioInputNodeProtocol { get }
    var mainMixerNode: AudioMixerNodeProtocol { get }
    var isRunning: Bool { get }

    func attach(_ player: AudioPlayerNodeProtocol)
    func connect(_ player: AudioPlayerNodeProtocol, to mixer: AudioMixerNodeProtocol, format: AVAudioFormat)
    func prepare()
    func start() throws
    func stop()
}

protocol AudioPlayerNodeProtocol: AnyObject {
    var volume: Float { get set }
    var isPlaying: Bool { get }
    func play()
    func stop()
    func scheduleBuffer(_ buffer: AVAudioPCMBuffer, completionHandler: AVAudioNodeCompletionHandler?)
    /// Underlying AVAudioPlayerNode (or nil for fakes). Only used where AVAudioEngine.attach/connect demand the raw type.
    var underlyingPlayerNode: AVAudioPlayerNode? { get }
}

protocol AudioInputNodeProtocol: AnyObject {
    func inputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat
    func setVoiceProcessingEnabled(_ enabled: Bool) throws
    var isVoiceProcessingAGCEnabled: Bool { get set }
    func installTap(
        onBus bus: AVAudioNodeBus,
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat?,
        block: @escaping AVAudioNodeTapBlock,
    )
    func removeTap(onBus bus: AVAudioNodeBus)
}

protocol AudioMixerNodeProtocol: AnyObject {
    var outputVolume: Float { get set }
}

// MARK: - Production wrappers

final class RealAudioEngine: AudioEngineProtocol {
    let engine: AVAudioEngine
    let inputNode: AudioInputNodeProtocol
    let mainMixerNode: AudioMixerNodeProtocol

    init() {
        let engine = AVAudioEngine()
        self.engine = engine
        inputNode = RealInputNode(node: engine.inputNode)
        mainMixerNode = RealMixerNode(node: engine.mainMixerNode)
    }

    var isRunning: Bool {
        engine.isRunning
    }

    func attach(_ player: AudioPlayerNodeProtocol) {
        if let real = player.underlyingPlayerNode {
            engine.attach(real)
        }
    }

    func connect(_ player: AudioPlayerNodeProtocol, to mixer: AudioMixerNodeProtocol, format: AVAudioFormat) {
        guard let realPlayer = player.underlyingPlayerNode,
              let realMixer = (mixer as? RealMixerNode)?.node
        else { return }
        engine.connect(realPlayer, to: realMixer, format: format)
    }

    func prepare() {
        engine.prepare()
    }

    func start() throws {
        try engine.start()
    }

    func stop() {
        engine.stop()
    }
}

final class RealInputNode: AudioInputNodeProtocol {
    let node: AVAudioInputNode
    init(node: AVAudioInputNode) {
        self.node = node
    }

    func inputFormat(forBus bus: AVAudioNodeBus) -> AVAudioFormat {
        node.inputFormat(forBus: bus)
    }

    func setVoiceProcessingEnabled(_ enabled: Bool) throws {
        try node.setVoiceProcessingEnabled(enabled)
    }

    var isVoiceProcessingAGCEnabled: Bool {
        get { node.isVoiceProcessingAGCEnabled }
        set { node.isVoiceProcessingAGCEnabled = newValue }
    }

    func installTap(
        onBus bus: AVAudioNodeBus,
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat?,
        block: @escaping AVAudioNodeTapBlock,
    ) {
        node.installTap(onBus: bus, bufferSize: bufferSize, format: format, block: block)
    }

    func removeTap(onBus bus: AVAudioNodeBus) {
        node.removeTap(onBus: bus)
    }
}

final class RealMixerNode: AudioMixerNodeProtocol {
    let node: AVAudioMixerNode
    init(node: AVAudioMixerNode) {
        self.node = node
    }

    var outputVolume: Float {
        get { node.outputVolume }
        set { node.outputVolume = newValue }
    }
}

final class RealAudioPlayerNode: AudioPlayerNodeProtocol {
    let node: AVAudioPlayerNode
    init(node: AVAudioPlayerNode = AVAudioPlayerNode()) {
        self.node = node
    }

    var volume: Float {
        get { node.volume }
        set { node.volume = newValue }
    }

    var isPlaying: Bool {
        node.isPlaying
    }

    func play() {
        node.play()
    }

    func stop() {
        node.stop()
    }

    func scheduleBuffer(_ buffer: AVAudioPCMBuffer, completionHandler: AVAudioNodeCompletionHandler?) {
        node.scheduleBuffer(buffer, completionHandler: completionHandler)
    }

    var underlyingPlayerNode: AVAudioPlayerNode? {
        node
    }
}
