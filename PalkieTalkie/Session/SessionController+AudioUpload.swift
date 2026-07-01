import Foundation
import OSLog
import UIKit

private let logger = Logger(subsystem: "com.palkietalkie", category: "conversation")

/// Post-session audio upload, split out of SessionController to keep that type within SwiftLint's body-length budget.
extension SessionController {
    /// Move both freshly-recorded tracks (mic = user, model = AI) into the durable outbox, then flush it, under a background-task assertion so leaving the Talk tab or backgrounding doesn't suspend the work mid-transfer. Enqueue-then-flush (rather than upload-inline) is the fix for the "model present, mic absent" sessions: the old path deleted each wav right after attempting its POST, so any single failed upload lost that recording with no retry. Now a failed track stays queued and is retried on the next flush (next session end or next app launch), and the two tracks are independent, so one failing never drops the other.
    func uploadSessionAudio(sessionId: String, streamer: AudioStreamerType) async {
        let bgTask = UIApplication.shared.beginBackgroundTask(withName: "session-audio-upload")
        defer { UIApplication.shared.endBackgroundTask(bgTask) }
        await enqueueRecordedTrack(sessionId: sessionId, source: "mic", url: streamer.recordedSessionAudioURL)
        await enqueueRecordedTrack(sessionId: sessionId, source: "model", url: streamer.recordedModelAudioURL)
        await flushAudioOutbox()
    }

    /// Read a finalized wav off disk, deflate it, drop it in the outbox, delete the original. Best-effort: a missing/empty/unreadable recording is simply skipped (nothing to upload). The deflated payload now lives in the outbox, so deleting the raw wav here is safe even if the upload later fails.
    private func enqueueRecordedTrack(sessionId: String, source: String, url: URL?) async {
        guard let url else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        guard let wavData = try? Data(contentsOf: url), !wavData.isEmpty else { return }
        // Apple's `NSData.compressed(using: .zlib)` produces a RAW DEFLATE stream (no zlib wrapper, no gzip header); the upload's Content-Type ("audio/wav+deflate") matches. Do NOT mislabel it as "gzip".
        guard let deflated = try? (wavData as NSData).compressed(using: .zlib) as Data else { return }
        try? outbox.enqueue(sessionId: sessionId, source: source, deflatedWav: deflated)
    }

    /// Deliver everything queued, deleting each payload only on a confirmed upload. A failure keeps the payload for the next flush and reports one telemetry event so the failure is visible server-side (it was previously only a device-local `os_log` line, which is why the original loss left no trace to debug).
    func flushAudioOutbox() async {
        await outbox.flush { [backend] sessionId, source, data in
            do {
                if source == "mic" {
                    try await backend.uploadMicAudio(sessionId: sessionId, deflatedWav: data)
                } else {
                    try await backend.uploadModelAudio(sessionId: sessionId, deflatedWav: data)
                }
                return true
            } catch {
                logger
                    .error(
                        "audio upload failed (\(source, privacy: .public)): \(String(describing: error), privacy: .public)",
                    )
                await backend.reportAudioUploadFailed(
                    sessionId: sessionId, source: source, bytes: data.count, reason: String(describing: error),
                )
                return false
            }
        }
    }
}
