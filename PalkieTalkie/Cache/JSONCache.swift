import Foundation

/// Tiny Codable cache backed by UserDefaults. Used by tab views to render the last-known value on first appearance (and across app launches) without waiting on the network. Pair the load at @State init with a save inside the .task fetch, and you get stale-while-revalidate: the view shows yesterday's data instantly, then SwiftUI re-renders when fresh data arrives.
///
/// UserDefaults rather than a file in Documents/ because the cached payloads are small (a few KB at most) and the API is simpler. Anything larger than ~100 KB belongs in Documents/.
enum JSONCache {
    static func load<T: Decodable>(_: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? BackendAPI.decoder.decode(T.self, from: data)
    }

    static func save(_ value: some Encodable, key: String) {
        guard let data = try? BackendAPI.encoder.encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear(key: String) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
