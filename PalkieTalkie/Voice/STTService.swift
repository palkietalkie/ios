import Foundation
import Speech

/// Wraps Apple SpeechAnalyzer (iOS 26) for on-device speech-to-text.
/// TODO: Re-implement with current SpeechAnalyzer API. Init signatures
/// changed (now requires `modules:`, `locale:`, `preset:` parameters).
actor STTService {
    /// Download the English speech model if not already installed.
    func prepareModel() async throws {
        // TODO: AssetInventory.assetInstallationRequest(supporting:) call
    }

    /// Transcribe WAV audio data (16kHz) to text.
    func transcribe(_ audioData: Data) async throws -> String {
        throw STTError.notImplemented
    }
}

enum STTError: Error {
    case notImplemented
}
