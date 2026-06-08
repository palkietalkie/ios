@testable import PalkieTalkie
import XCTest

@MainActor
final class JSONCacheTests: XCTestCase {
    private let key = "JSONCacheTestsKey_\(UUID().uuidString)"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Save then load on the same key must round-trip exactly. Backbone of every tab's stale-while-revalidate cache.
    func testSaveThenLoadRoundTripsExact() {
        struct Row: Codable, Equatable { let id: Int; let name: String; let ok: Bool }
        let written = Row(id: 7, name: "Wes", ok: true)
        JSONCache.save(written, key: key)
        XCTAssertEqual(JSONCache.load(Row.self, key: key), written)
    }

    /// Missing key returns nil — the caller's first-render branch ("no cache, show empty state") depends on this. A refactor returning a default-constructed value would silently flash empty content as if it were cached.
    func testLoadReturnsNilOnMissingKey() {
        XCTAssertNil(JSONCache.load(Int.self, key: "JSONCacheTestsMissing_\(UUID().uuidString)"))
    }

    /// Type-mismatch returns nil rather than throwing. A backend rename of a field would otherwise crash every cold launch.
    func testLoadReturnsNilOnTypeMismatch() {
        JSONCache.save(["a", "b", "c"], key: key)
        XCTAssertNil(JSONCache.load(Int.self, key: key))
    }

    /// Subsequent save replaces — no merge, no append. Tab-view code assumes the cache reflects the latest fetch verbatim.
    func testSaveReplacesPreviousValue() {
        JSONCache.save("first", key: key)
        JSONCache.save("second", key: key)
        XCTAssertEqual(JSONCache.load(String.self, key: key), "second")
    }
}
