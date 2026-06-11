import Foundation
import OSLog

private let logger = Logger(subsystem: "com.palkietalkie", category: "conversation")

/// Post-session audio upload, split out of SessionController to keep that type within SwiftLint's body-length budget.
extension SessionController {
    /// Read the freshly-finalized mic wav from the streamer, deflate-compress it, POST to the backend, delete the local file. All steps best-effort; logs and continues on failure. Companion call below ships the model-output wav.
    func uploadMicAudioIfAny(sessionId: String, streamer: AudioStreamerType) async {
        guard let url = await streamer.recordedSessionAudioURL else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let wavData = try Data(contentsOf: url)
            guard !wavData.isEmpty else { return }
            // Apple's `NSData.compressed(using: .zlib)` produces a RAW DEFLATE stream — no zlib wrapper, no gzip header. The Content-Type the network layer sends ("audio/wav+deflate") matches; do NOT mislabel it as "gzip".
            let deflated = try (wavData as NSData).compressed(using: .zlib) as Data
            try await backend.uploadMicAudio(sessionId: sessionId, deflatedWav: deflated)
        } catch {
            logger.error("mic audio upload failed: \(String(describing: error), privacy: .public)")
        }
        await uploadModelAudioIfAny(sessionId: sessionId, streamer: streamer)
    }

    /// Mirror of `uploadMicAudioIfAny` for the model-output wav. Independent best-effort upload so a failure on one track doesn't poison the other.
    func uploadModelAudioIfAny(sessionId: String, streamer: AudioStreamerType) async {
        guard let url = await streamer.recordedModelAudioURL else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let wavData = try Data(contentsOf: url)
            guard !wavData.isEmpty else { return }
            let deflated = try (wavData as NSData).compressed(using: .zlib) as Data
            try await backend.uploadModelAudio(sessionId: sessionId, deflatedWav: deflated)
        } catch {
            logger.error("model audio upload failed: \(String(describing: error), privacy: .public)")
        }
    }
}
