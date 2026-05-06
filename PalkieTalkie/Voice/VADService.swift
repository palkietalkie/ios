import AVFoundation
import Foundation
import RealTimeCutVADLibrary

/// Wraps Silero v5 VAD to detect speech start/end from mic audio.
/// `@unchecked Sendable`: VADWrapper bridges to ObjC and dispatches its own threads;
/// callbacks fire from the VAD library's processing thread. We trust the underlying
/// library's thread-safety. Revisit when refactoring concurrency.
final class VADService: NSObject, @unchecked Sendable {
    private var vadWrapper: VADWrapper?

    var onVoiceStarted: (() -> Void)?
    var onVoiceEnded: ((Data) -> Void)?

    override init() {
        super.init()
        vadWrapper = VADWrapper()
        vadWrapper?.delegate = self
    }

    /// Feed 16kHz mono float32 audio from the mic tap.
    func process(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        vadWrapper?.processAudioData(withBuffer: channelData, count: UInt(count))
    }
}

extension VADService: VADDelegate {
    func voiceStarted() {
        onVoiceStarted?()
    }

    func voiceEnded(withWavData wavData: Data) {
        onVoiceEnded?(wavData)
    }

    func voiceDidContinue(withPCMFloat pcmFloatData: Data!) {
        // No-op: we only care about start/end events for now.
    }
}
