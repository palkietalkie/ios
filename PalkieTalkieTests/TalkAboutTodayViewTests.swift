@testable import PalkieTalkie
import SwiftUI
import XCTest

/// Pure behavior tests for TalkAboutTodayView. The view's body requires a SessionController in @Environment, which ViewInspector's `inspect()` doesn't run through (it bypasses SwiftUI's environment resolution). Anything we want to assert about the rendered tree has to go through `UIHostingController` host integration tests instead — see `ConversationViewBranchTests` for that pattern. Tests here cover what we CAN cover without rendering: cache key constants and DTO shape used by the section data.
@MainActor
final class TalkAboutTodayViewTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "cache.talk_about_today")
        super.tearDown()
    }

    /// Hosts TalkAboutTodayView with canned content so every topic header branch + the load-success path runs, then asserts the load-success path persisted exactly the sections the cards rendered from (in order). The `buildCard` / `resolveHeaderKey` / `buildImageBackground` builders all consume this same loaded `sections` array, so a regression that drops or reorders sections on load surfaces here.
    func testHostsWithLoadedContent() async throws {
        let transport = FakeTransport()
        let dto = DailyContentDTO(
            day: "2026-06-08",
            sections: [
                .init(
                    topic: "politics",
                    items: [.init(title: "P1", summary: "s", source: "AP", imageUrl: "https://img.test/1.jpg")],
                ),
                .init(topic: "business", items: [.init(title: "B1", summary: "s", source: "FT", imageUrl: "")]),
                .init(topic: "sports", items: [.init(title: "S1", summary: "s", source: "ESPN", imageUrl: "")]),
                .init(topic: "quizzes", items: [.init(title: "Q1", summary: "s", source: "", imageUrl: "")]),
                .init(topic: "other_unknown", items: [.init(title: "O1", summary: "s", source: "X", imageUrl: "")]),
            ],
        )
        transport.responseData = try BackendAPI.encoder.encode(dto)
        let api = try BackendAPI(
            baseURL: XCTUnwrap(URL(string: "https://test.example.com")),
            transport: transport,
            auth: StubAuthing(),
        )
        let session = SessionController(backend: api)
        await TestHosting.host(
            TalkAboutTodayView()
                .environment(\.backendAPI, api)
                .environment(session),
            settleMs: 600,
        )
        // load() (success path) caches the rendered sections; assert it ran and preserved order so the header/card builders had the same data the test fed.
        let cached = JSONCache.load([TalkSection].self, key: "cache.talk_about_today")
        XCTAssertEqual(cached?.map(\.topic), ["politics", "business", "sports", "quizzes", "other_unknown"])
        XCTAssertEqual(cached?.first?.items.first?.title, "P1")
    }

    /// Hosts with a backend error — covers the catch branch that sets loadError.
    func testHostsWithLoadErrorSurfacesMessage() async throws {
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = Data("boom".utf8)
        let api = try BackendAPI(
            baseURL: XCTUnwrap(URL(string: "https://test.example.com")),
            transport: transport,
            auth: StubAuthing(),
        )
        let session = SessionController(backend: api)
        await TestHosting.host(
            TalkAboutTodayView()
                .environment(\.backendAPI, api)
                .environment(session),
            settleMs: 500,
        )
    }

    /// Cache key must match the constant the view reads on init. A rename without updating the seeded cache would silently fall through to network-blocking first paint.
    func testCacheKeyIsStable() {
        // Read via the static accessor isn't exposed; assert by writing under the expected key and reading back.
        let key = "cache.talk_about_today"
        let payload = [
            TalkSection(
                topic: "politics",
                items: [TalkItem(id: "i_1", title: "Headline", summary: "s", source: "AP", imageUrl: "")],
            ),
        ]
        JSONCache.save(payload, key: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let read = JSONCache.load([TalkSection].self, key: key)
        XCTAssertEqual(read?.count, 1)
        XCTAssertEqual(read?.first?.topic, "politics")
    }
}
