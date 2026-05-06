import AVFoundation
import Foundation

// TERMINOLOGY:
// - `AVAudioEngine`: Apple's audio processing graph (like Web Audio API's AudioContext).
//   Connects audio nodes (mic input → processing → speaker output) in a graph.
// - `AVAudioPlayerNode`: A node that plays audio buffers (like AudioBufferSourceNode in Web Audio).
// - `AVAudioPCMBuffer`: Raw audio data in memory (like a Float32Array of audio samples).
// - `AVAudioSession`: System-level audio configuration (which hardware to use, mixing behavior).
//   `.playAndRecord` = use both mic and speaker simultaneously.
//   `.voiceChat` = optimize for voice (enables echo cancellation, noise suppression).
// - `installTap`: Attaches a callback to an audio node that receives audio buffers in real-time.
//   Like `audioNode.addEventListener('audioprocess', callback)` in Web Audio.
// - `AVAudioConverter`: Converts between audio formats (sample rates, channel counts).
// - `throws`: Function can throw errors (like throwing exceptions in JS/Python).
//   Callers must use `try` (like try/catch but enforced by the compiler).
// - `// MARK: -`: Section dividers in Xcode's code navigator (cosmetic, like #region in C#).

/// Manages AVAudioEngine for continuous mic capture and TTS playback.
/// Engine stays running at all times — never stop/start between turns.
/// `@unchecked Sendable`: AVAudioEngine has its own real-time audio thread; the
/// `installTap` callback fires off-main. We trust AVAudioEngine's threading.
final class AudioPipeline: @unchecked Sendable {
    let engine = AVAudioEngine()
    let playerNode = AVAudioPlayerNode()

    /// Called with mic audio buffers (16kHz mono float32)
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    private let targetSampleRate: Double = 16_000
    private var converter: AVAudioConverter?

    init() {
        engine.attach(playerNode)
        engine.connect(
            playerNode,
            to: engine.mainMixerNode,
            format: nil
        )
    }

    func start() throws {
        try configureAudioSession()
        installMicTap()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        engine.stop()
    }

    // MARK: - Playback

    func scheduleBuffer(_ buffer: AVAudioPCMBuffer) {
        playerNode.scheduleBuffer(buffer)
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    func stopPlayback() {
        playerNode.stop()
    }

    var isPlaying: Bool {
        playerNode.isPlaying
    }

    // MARK: - Private

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
        try session.setActive(true)
    }

    private func installMicTap() {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!

        if inputFormat.sampleRate != targetSampleRate || inputFormat.channelCount != 1 {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        }

        inputNode.installTap(onBus: 0, bufferSize: 512, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            if let converter = self.converter {
                let frameCount = AVAudioFrameCount(
                    Double(buffer.frameLength) * self.targetSampleRate / inputFormat.sampleRate
                )
                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: targetFormat,
                    frameCapacity: frameCount
                ) else { return }

                var error: NSError?
                converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                if error == nil {
                    self.onAudioBuffer?(convertedBuffer)
                }
            } else {
                self.onAudioBuffer?(buffer)
            }
        }
    }
}
