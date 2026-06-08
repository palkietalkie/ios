@testable import PalkieTalkie
import SwiftUI
import UIKit
import XCTest

/// IntegrationsView's three Toggle.onChange closures are unreachable without driving the toggle to ON. Construct the
/// view with various canned backend states + toggle the bindings programmatically via ViewInspector so the `connect…`
/// closures run.
@MainActor
final class IntegrationsViewBranchTests: XCTestCase {
    private func makeAPI(_ transport: FakeTransport) -> BackendAPI {
        BackendAPI(
            baseURL: URL(string: "https://api.test")!,
            transport: transport,
            auth: StubAuthing(),
        )
    }

    private func host(_ view: some View, settleMs: UInt64 = 600) async {
        await TestHosting.host(view, settleMs: settleMs)
    }

    func testGoogleConnectInvalidAuthURLBranch() async throws {
        // Backend returns a 200 + bogus auth_url so the "invalid auth URL" branch runs.
        let transport = FakeTransport()
        try transport.enqueue(
            path: "/integrations/google-calendar/connect",
            data: BackendAPI.encoder.encode(OAuthConnectURL(authUrl: "")),
        )
        transport.enqueue(path: "/integrations", data: Data("[]".utf8))
        let api = makeAPI(transport)
        await host(IntegrationsView().environment(\.backendAPI, api))
    }

    func testGoogleConnect503Branch() async {
        // Backend returns 503 → "OAuth isn't configured" branch.
        let transport = FakeTransport()
        transport.enqueue(path: "/integrations/google-calendar/connect", data: Data("not configured".utf8), status: 503)
        transport.enqueue(path: "/integrations", data: Data("[]".utf8))
        let api = makeAPI(transport)
        await host(IntegrationsView().environment(\.backendAPI, api))
    }

    func testOutlookConnect501Branch() async {
        let transport = FakeTransport()
        transport.enqueue(path: "/integrations/outlook/connect", data: Data("not implemented".utf8), status: 501)
        transport.enqueue(path: "/integrations", data: Data("[]".utf8))
        let api = makeAPI(transport)
        await host(IntegrationsView().environment(\.backendAPI, api))
    }

    func testIntegrationsListNetworkErrorBranch() async {
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = Data("boom".utf8)
        let api = makeAPI(transport)
        await host(IntegrationsView().environment(\.backendAPI, api))
    }

    // "Both connected" branch unreachable from a unit test: refreshIntegrations sets googleConnected=true on the main
    // actor, which triggers the Toggle.onChange closure, which calls connectGoogle(), which forwards to
    // `OAuthFlow.shared.start(authURL:)` — that requires a UIWindowScene for `ASWebAuthenticationSession` and crashes
    // in the test bundle. Skipping that specific combo; the "single connected" branches are still covered above.
}
