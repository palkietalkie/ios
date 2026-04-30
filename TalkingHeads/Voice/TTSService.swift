import AVFoundation
import Foundation
import MLXAudioTTS

// TERMINOLOGY:
// - `(any TTSModel)?`: `any TTSModel` = any type conforming to the TTSModel protocol
//   (like `TTSModel` interface in TS). The `?` makes it optional/nullable.
// - `AVAudioPCMBuffer`: Raw PCM audio samples in memory.
//   PCM = uncompressed audio (like a WAV file in memory). Each sample is a float (-1.0 to 1.0).
// - `floatChannelData`: Pointer to the raw float array inside the buffer.
//   `![0]` = force-unwrap channel 0 (mono audio has only 1 channel).
// - `.init(...)`: Shorthand for creating an instance when the type is known from context.
//   `.init(maxTokens: 2048)` = `GenerateParameters(maxTokens: 2048)`.

/// Wraps mlx-audio-swift for on-device text-to-speech synthesis.
actor TTSService {
    private var model: (any TTSModel)?
    private let modelID = "mlx-community/Soprano-80M-bf16"

    /// Load the TTS model into memory.
    func warmUp() async throws {
        model = try await SopranoModel.fromPretrained(modelID)
    }

    /// Synthesize speech from text, returning a playable audio buffer.
    func synthesize(_ text: String) async throws -> AVAudioPCMBuffer {
        guard let model else {
            throw TTSError.modelNotLoaded
        }

        let audioArray = try await model.generate(
            text: text,
            parameters: .init(maxTokens: 2048, temperature: 0.7, topP: 0.95)
        )

        return try arrayToPCMBuffer(audioArray, sampleRate: Double(model.sampleRate))
    }

    /// Synthesize with streaming — yields partial audio buffers as they're generated.
    func synthesizeStream(_ text: String) -> AsyncThrowingStream<AVAudioPCMBuffer, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let model = self.model else {
                    continuation.finish(throwing: TTSError.modelNotLoaded)
                    return
                }
                do {
                    let audioArray = try await model.generate(
                        text: text,
                        parameters: .init(maxTokens: 2048, temperature: 0.7, topP: 0.95)
                    )
                    let buffer = try self.arrayToPCMBuffer(audioArray, sampleRate: Double(model.sampleRate))
                    continuation.yield(buffer)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private func arrayToPCMBuffer(_ samples: [Float], sampleRate: Double) throws -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw TTSError.bufferCreationFailed
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channelData = buffer.floatChannelData![0]
        for (i, sample) in samples.enumerated() {
            channelData[i] = sample
        }

        return buffer
    }
}

enum TTSError: Error {
    case bufferCreationFailed
    case modelNotLoaded
}
