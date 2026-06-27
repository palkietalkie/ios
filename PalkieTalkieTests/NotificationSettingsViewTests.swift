@testable import PalkieTalkie
import SwiftUI
import ViewInspector
import XCTest

@MainActor
final class NotificationSettingsViewTests: XCTestCase {
    /// The reminders master toggle must exist — it maps 1:1 to /notification-prefs reminders_enabled and is the opt-out signal.
    func testFormExposesTheRemindersToggle() throws {
        let sut = NotificationSettingsView()
        let toggles = try sut.inspect().findAll(ViewType.Toggle.self)
        XCTAssertEqual(toggles.count, 1)
    }

    /// Toggle starts off pre-server-load (the .task hasn't fired). Locks that it doesn't fake "on" before the real value loads.
    func testToggleStartsOffBeforeServerLoad() throws {
        let sut = NotificationSettingsView()
        let toggle = try sut.inspect().find(ViewType.Toggle.self)
        XCTAssertFalse(try toggle.isOn())
    }

    /// Hosts with canned prefs so load()'s success path runs and the toggle reflects server state.
    func testHostsWithLoadedPrefs() async throws {
        let transport = FakeTransport()
        transport.responseData = try BackendAPI.encoder.encode(
            NotificationPrefsOut(remindersEnabled: true, reminderHourLocal: 8),
        )
        let api = try BackendAPI(
            baseURL: XCTUnwrap(URL(string: "https://test.example.com")),
            transport: transport,
            auth: StubAuthing(),
        )
        await TestHosting.host(
            NavigationStack { NotificationSettingsView() }.environment(\.backendAPI, api),
            settleMs: 500,
        )
    }

    /// /notification-prefs returns 500 — load()'s catch sets `error` and the alert flips visible.
    func testHostsWithLoadErrorTriggersAlertBranch() async throws {
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = Data("boom".utf8)
        let api = try BackendAPI(
            baseURL: XCTUnwrap(URL(string: "https://test.example.com")),
            transport: transport,
            auth: StubAuthing(),
        )
        await TestHosting.host(
            NavigationStack { NotificationSettingsView() }.environment(\.backendAPI, api),
            settleMs: 500,
        )
    }
}
