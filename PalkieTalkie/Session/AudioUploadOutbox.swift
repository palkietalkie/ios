import Foundation

/// Durable retry queue for session-audio uploads. Same shape as `CrashStore`: persist the payload to disk now, deliver it whenever the network lets us, delete only on a confirmed 2xx. The old path deflate-compressed the wav and POSTed it inline, deleting the local file in a `defer` whether or not the upload succeeded, so a single failed upload (a stalled cellular uplink, a network drop, the app suspending mid-POST) lost the recording forever with no retry. That's the most likely reason a long session landed with model audio but no mic track.
///
/// A pending file is named `<sessionId>__<source>.wavd` and holds the already-deflated bytes ready to POST verbatim, so a flush is a plain read + upload with no re-compression. `dir` is injectable so tests write to a throwaway directory instead of the real caches folder.
struct AudioUploadOutbox {
    let dir: URL

    static let `default` = AudioUploadOutbox(
        dir: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pending_audio_uploads", isDirectory: true),
    )

    struct Pending {
        let url: URL
        let sessionId: String
        let source: String
    }

    /// Write the deflated payload into the queue. `.atomic` so a crash mid-write never leaves a half-file a later flush would POST as truncated audio.
    func enqueue(sessionId: String, source: String, deflatedWav: Data) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(sessionId)__\(source).wavd")
        try deflatedWav.write(to: url, options: .atomic)
    }

    func pending() -> [Pending] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return urls.compactMap { url in
            // sessionId is a UUID (no "__"), so a single "__" split cleanly recovers both fields.
            let parts = url.deletingPathExtension().lastPathComponent.components(separatedBy: "__")
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            return Pending(url: url, sessionId: parts[0], source: parts[1])
        }
    }

    func remove(_ pending: Pending) {
        try? FileManager.default.removeItem(at: pending.url)
    }

    /// Attempt every queued upload. `upload` returns true only on a confirmed delivery; a delivered payload is removed, a failed one stays for the next flush (next app launch, next session end, next foreground). A payload that can't even be read off disk is dropped so it can't wedge the queue. Returns the count delivered this pass.
    @discardableResult
    func flush(upload: @Sendable (_ sessionId: String, _ source: String, _ deflatedWav: Data) async -> Bool) async
        -> Int
    {
        var delivered = 0
        for item in pending() {
            guard let data = try? Data(contentsOf: item.url) else {
                remove(item)
                continue
            }
            if await upload(item.sessionId, item.source, data) {
                remove(item)
                delivered += 1
            }
        }
        return delivered
    }
}
