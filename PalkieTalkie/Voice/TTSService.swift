import AVFoundation
import Foundation

/// Wraps mlx-audio-swift for on-device text-to-speech synthesis.
/// TODO: Re-implement with current MLXAudioTTS API (SpeechGenerationModel).
/// The previous implementation used outdated `TTSModel` protocol that no longer exists.
actor TTSService {
    /// Load the TTS model into memory.
    func warmUp() async throws {
        // TODO: load SopranoModel via TTS.loadModel(modelRepo:)
    }

    /// Synthesize speech from text, returning a playable audio buffer.
    func synthesize(_ text: String) async throws -> sending AVAudioPCMBuffer {
        throw TTSError.notImplemented
    }

    /// Synthesize with streaming — yields partial audio buffers as they're generated.
    func synthesizeStream(_ text: String) -> AsyncThrowingStream<AVAudioPCMBuffer, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: TTSError.notImplemented)
        }
    }
}

enum TTSError: Error {
    case bufferCreationFailed
    case modelNotLoaded
    case notImplemented
}
