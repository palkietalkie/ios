@testable import PalkieTalkie
import SwiftUI
import XCTest

/// Hosts RootView with canned BackendAPI responses so each post-loading branch evaluates — sign-in (clerk.user == nil branch always hits because tests never sign in), consent-set or unset gate, profile-complete gate.
@MainActor
final class RootViewBranchTests: XCTestCase {
    private func makeAPI(_ transport: FakeTransport) -> BackendAPI {
        BackendAPI(baseURL: URL(string: "https://test.example.com")!, transport: transport, auth: StubAuthing())
    }

    /// Consent endpoint returns set=true — drives the loadGatesIfNeeded happy path beyond the consent gate.
    func testHostingWithConsentSet() async throws {
        let transport = FakeTransport()
        let consent = ConsentDTO(personalization: true, productImprovement: true, set: true)
        try transport.enqueue(path: "/consent", data: BackendAPI.encoder.encode(consent))
        let api = makeAPI(transport)
        await TestHosting.host(RootView().environment(\.backendAPI, api), settleMs: 600)
    }

    /// Consent endpoint returns set=false — drives the gate-still-needed branch.
    func testHostingWithConsentNotSet() async throws {
        let transport = FakeTransport()
        let consent = ConsentDTO(personalization: false, productImprovement: false, set: false)
        try transport.enqueue(path: "/consent", data: BackendAPI.encoder.encode(consent))
        let api = makeAPI(transport)
        await TestHosting.host(RootView().environment(\.backendAPI, api), settleMs: 600)
    }

    /// Backend errors on consent — drives the fail-open catch (consentSet = true).
    func testHostingWithConsentErrorFailsOpen() async {
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = Data("nope".utf8)
        let api = makeAPI(transport)
        await TestHosting.host(RootView().environment(\.backendAPI, api), settleMs: 600)
    }

    /// Signed-out (no Clerk user in tests) → resolveRootDestination returns .signIn, so RootView renders SignInView through the new switch without crashing.
    func testHostingSignedOutRendersSignInBranch() async {
        let api = makeAPI(FakeTransport())
        await TestHosting.host(RootView().environment(\.backendAPI, api), settleMs: 300)
    }
}
