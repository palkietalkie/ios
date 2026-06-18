@testable import PalkieTalkie
import SwiftUI
import ViewInspector
import XCTest

@MainActor
final class PrivacyDataViewTests: XCTestCase {
    /// Two opt-in/opt-out toggles must be exposed — Personalization + Product improvement. They map 1:1 to backend's /consent endpoint fields. A refactor that collapses them or hides one silently breaks the contract.
    func testFormExposesExactlyTwoToggles() throws {
        let sut = PrivacyDataView()
        let toggles = try sut.inspect().findAll(ViewType.Toggle.self)
        XCTAssertEqual(toggles.count, 2)
    }

    /// A functional "Delete my account" button exists (App Store Guideline 5.1.1(v) requires in-app account deletion). The earlier non-functional "Coming soon" history/export rows were removed — shipping placeholder screens risks review rejection.
    func testDeleteAccountButtonExists() throws {
        let sut = PrivacyDataView()
        XCTAssertNoThrow(try sut.inspect().find(button: "Delete my account"))
    }

    /// Both toggles start at false because the .task hasn't fired yet in the inspected tree. The actual default is "load from server on first appear". Locking the pre-load state so a refactor that pre-pops them with `true` doesn't silently fake server state.
    func testTogglesStartFalseBeforeServerLoad() throws {
        let sut = PrivacyDataView()
        let toggles = try sut.inspect().findAll(ViewType.Toggle.self)
        for toggle in toggles {
            XCTAssertFalse(try toggle.isOn(), "expected toggles to start off (pre-server-load)")
        }
    }

    /// Hosts PrivacyDataView with canned /consent so load()'s success path runs and toggles reflect server state.
    func testHostsWithLoadedConsent() async throws {
        let transport = FakeTransport()
        transport.responseData = try BackendAPI.encoder.encode(
            ConsentDTO(personalization: true, productImprovement: true, set: true),
        )
        let api = try BackendAPI(
            baseURL: XCTUnwrap(URL(string: "https://test.example.com")),
            transport: transport,
            auth: StubAuthing(),
        )
        await TestHosting.host(NavigationStack { PrivacyDataView() }.environment(\.backendAPI, api), settleMs: 500)
    }

    /// /consent returns 500 — load()'s catch sets `error`, the alert flips visible. Same code path as ConsentView's error-alert but for the More-tab variant.
    func testHostsWithLoadErrorTriggersAlertBranch() async throws {
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = Data("boom".utf8)
        let api = try BackendAPI(
            baseURL: XCTUnwrap(URL(string: "https://test.example.com")),
            transport: transport,
            auth: StubAuthing(),
        )
        await TestHosting.host(NavigationStack { PrivacyDataView() }.environment(\.backendAPI, api), settleMs: 500)
    }
}
