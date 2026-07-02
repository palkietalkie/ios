import Foundation

/// Reads/writes the single pending CrashRecord to disk. One slot: the most recent crash overwrites any older unsent one (a crash loop reports its latest, not an unbounded backlog). The URL is injectable so tests don't touch the real caches directory.
struct CrashStore {
    let url: URL

    static let `default` = CrashStore(
        url: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pending_crash.json"),
    )

    func save(_ record: CrashRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func load() -> CrashRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CrashRecord.self, from: data)
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
