import Foundation
import Speech

// TERMINOLOGY:
// - `SpeechAnalyzer`: Apple's new on-device STT engine (iOS 26+). Replaces SFSpeechRecognizer.
//   All processing happens locally — no network calls, no cloud, complete privacy.
// - `SpeechTranscriber`: A "module" you attach to SpeechAnalyzer to get transcription results.
// - `AssetInventory`: Manages downloadable assets (like ML model files) from Apple's servers.
//   The speech model is ~100MB and downloaded once on first use.
// - `defer`: Runs code when the current scope exits (like `finally` in try/finally).
//   Used here to clean up the temp file regardless of success/failure.
// - `async throws`: Function is both async (returns a Promise) and can throw errors.
//   Must be called with `try await` (combines await + try/catch).

/// Wraps Apple SpeechAnalyzer (iOS 26) for on-device speech-to-text.
final class STTService {
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?

    init() {}

    /// Download the English speech model if not already installed.
    func prepareModel() async throws {
        let request = AssetInventory.assetInstallationRequest(supporting: Locale(identifier: "en-US"))
        try await request.downloadAndInstall()
    }

    /// Transcribe WAV audio data (16kHz) to text.
    func transcribe(_ audioData: Data) async throws -> String {
        let analyzer = SpeechAnalyzer()
        let transcriber = SpeechTranscriber()
        analyzer.addModule(transcriber)

        self.analyzer = analyzer
        self.transcriber = transcriber

        // Write audio data to a temporary file for SpeechAnalyzer
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        try audioData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await analyzer.analyze(audioFrom: tempURL)

        let transcript = transcriber.transcript.bestTranscription
        return transcript
    }
}
