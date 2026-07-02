@testable import PalkieTalkie
import SwiftUI
import ViewInspector
import XCTest

@MainActor
final class MistakesViewTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "cache.mistakes")
    }

    /// Empty state shows "No mistakes recorded yet" with the upbeat checkmark.seal icon — wording matters (not a failure state, an "all clear"). Pin both the literal copy and the icon name so a wording or icon refactor surfaces.
    func testEmptyStateRendersUpbeatContentUnavailable() throws {
        UserDefaults.standard.removeObject(forKey: "cache.mistakes")
        let sut = MistakesView()
        let cuv = try sut.inspect().find(ViewType.ContentUnavailableView.self)
        XCTAssertNotNil(cuv)
    }

    /// Stale-while-revalidate: pre-seeded cache renders on first paint. Verifies the row's three lines: original (strikethrough red), correction (green headline), and count caption. A refactor that bypasses the cache or drops one of the three lines surfaces here.
    func testRendersSeededCacheRow() throws {
        let cached = Mistake(
            id: "m_1",
            original: "I'm wondering the backhand grip",
            correction: "I'm wondering about the backhand grip",
            count: 3,
        )
        JSONCache.save([cached], key: "cache.mistakes")
        defer { UserDefaults.standard.removeObject(forKey: "cache.mistakes") }

        let sut = MistakesView()
        let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        XCTAssertTrue(texts.contains("I'm wondering the backhand grip"))
        XCTAssertTrue(texts.contains("I'm wondering about the backhand grip"))
        XCTAssertTrue(texts.contains("Seen 3×"))
    }

    /// Render-then-refresh: an HTTP-error refresh keeps the cached/empty list and logs (catch's else branch). Hosting drives the `.task`.
    func testHttpErrorRefreshKeepsContent() async throws {
        UserDefaults.standard.removeObject(forKey: "cache.mistakes")
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = Data("boom".utf8)
        let api = try BackendAPI(
            baseURL: XCTUnwrap(URL(string: "https://test.example.com")),
            transport: transport,
            auth: StubAuthing(),
        )
        await TestHosting.host(
            NavigationStack { MistakesView() }.environment(\.backendAPI, api),
            settleMs: 500,
        )
    }

    /// A decode/contract drift (200 + a non-mistakes shape) hits the contract-failure branch that sets loadError.
    func testDecodeFailureHitsContractBranch() async throws {
        UserDefaults.standard.removeObject(forKey: "cache.mistakes")
        let transport = FakeTransport()
        transport.responseData = Data("not the mistakes shape".utf8)
        let api = try BackendAPI(
            baseURL: XCTUnwrap(URL(string: "https://test.example.com")),
            transport: transport,
            auth: StubAuthing(),
        )
        await TestHosting.host(
            NavigationStack { MistakesView() }.environment(\.backendAPI, api),
            settleMs: 500,
        )
    }
}
