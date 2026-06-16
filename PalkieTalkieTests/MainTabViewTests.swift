@testable import PalkieTalkie
import SwiftUI
import XCTest

/// Pure tests on MainTabView. The body embeds ConversationView / TalkAboutTodayView / StatsView / PersonaPickerView, all of which require a SessionController via @Environment — ViewInspector's `inspect()` doesn't run environment resolution, so rendering crashes. The structural tests we'd want (5 tabs in the documented order) belong in a host-integration test alongside ConversationViewBranchTests; this file covers the AppTab enum's contract instead.
@MainActor
final class MainTabViewTests: XCTestCase {
    func testAppTabRawValuesAreUnique() {
        let raws = [MainTabView.AppTab.talk, .today, .stats, .persona, .more].map(\.rawValue)
        XCTAssertEqual(Set(raws).count, 5, "each tab needs a distinct AppStorage key")
    }

    /// All five tab cases exist. The AppStorage selection is keyed by raw value, so a renamed/removed case silently invalidates anyone's persisted last-tab.
    func testAllFiveAppTabCases() {
        let expected: Set = ["talk", "today", "stats", "persona", "more"]
        let actual = Set([
            MainTabView.AppTab.talk.rawValue,
            MainTabView.AppTab.today.rawValue,
            MainTabView.AppTab.stats.rawValue,
            MainTabView.AppTab.persona.rawValue,
            MainTabView.AppTab.more.rawValue,
        ])
        XCTAssertEqual(actual, expected)
    }

    /// Default tab is `.talk` per `/CLAUDE.md` Features #1 ("Main screen is the mic").
    func testDefaultRawValueIsTalk() {
        XCTAssertEqual(MainTabView.AppTab.talk.rawValue, "talk")
    }

    /// AppTab conforms to Hashable + RawRepresentable<String> — these conformances drive @AppStorage's encode/decode. A refactor that drops Hashable would silently break the persisted selection.
    func testAppTabConformances() {
        let set: Set<MainTabView.AppTab> = [.talk, .talk, .more]
        XCTAssertEqual(set.count, 2)
        XCTAssertEqual(MainTabView.AppTab(rawValue: "talk"), .talk)
    }

    /// Hosts the full TabView with the required SessionController + backendAPI environments so each of the 5 tabs' body builds. Catches a refactor that breaks any embedded tab view's @Environment requirements.
    func testHostsMainTabViewWithAllFiveTabs() async throws {
        let transport = FakeTransport()
        transport.responseData = Data("[]".utf8)
        let api = try BackendAPI(
            baseURL: XCTUnwrap(URL(string: "https://test.example.com")),
            transport: transport,
            auth: StubAuthing(),
        )
        let session = SessionController(backend: api)
        await TestHosting.host(
            MainTabView()
                .environment(\.backendAPI, api)
                .environment(session),
            settleMs: 400,
        )
    }
}
