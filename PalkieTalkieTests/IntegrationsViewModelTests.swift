@testable import PalkieTalkie
import XCTest

/// Direct tests for IntegrationsViewModel — drives connectGoogle / connectOutlook through every catch branch by injecting a fake OAuthStarting that throws the canned errors. The view tests cover rendering; this covers the catch logic that was previously unreachable from XCTest (OAuthFlow.shared.start requires a UIWindowScene).
@MainActor
final class IntegrationsViewModelTests: XCTestCase {
    private func makeAPI(_ transport: FakeTransport) -> BackendAPI {
        BackendAPI(baseURL: URL(string: "https://test.example.com")!, transport: transport, auth: StubAuthing())
    }

    private struct FakeOAuth: OAuthStarting {
        let error: Error?
        func start(authURL _: URL) async throws {
            if let error { throw error }
        }
    }

    func testInitHasDefaults() {
        let vm = IntegrationsViewModel()
        XCTAssertFalse(vm.googleConnected)
        XCTAssertFalse(vm.outlookConnected)
        XCTAssertNil(vm.statusMessage)
        XCTAssertFalse(vm.isLoading)
    }

    func testConnectGoogleSuccessRefreshesAndClearsStatus() async throws {
        let transport = FakeTransport()
        try transport.enqueue(
            path: "/integrations/google-calendar/connect",
            data: BackendAPI.encoder.encode(OAuthConnectURL(authUrl: "https://example.test/oauth")),
        )
        try transport.enqueue(
            path: "/integrations",
            data: BackendAPI.encoder.encode([IntegrationStatus(provider: "google", connected: true, expiresAt: nil)]),
        )
        let api = makeAPI(transport)
        let vm = IntegrationsViewModel(oauth: FakeOAuth(error: nil))
        await vm.connectGoogle(api: api)
        XCTAssertTrue(vm.googleConnected)
        XCTAssertNil(vm.statusMessage)
    }

    func testConnectGoogleInvalidAuthURLSetsStatus() async throws {
        let transport = FakeTransport()
        try transport.enqueue(
            path: "/integrations/google-calendar/connect",
            data: BackendAPI.encoder.encode(OAuthConnectURL(authUrl: "")),
        )
        let api = makeAPI(transport)
        let vm = IntegrationsViewModel(oauth: FakeOAuth(error: nil))
        await vm.connectGoogle(api: api)
        XCTAssertEqual(vm.statusMessage, "Backend returned an invalid auth URL.")
        XCTAssertFalse(vm.googleConnected)
    }

    func testConnectGoogleUserCancelledSetsStatus() async throws {
        let transport = FakeTransport()
        try transport.enqueue(
            path: "/integrations/google-calendar/connect",
            data: BackendAPI.encoder.encode(OAuthConnectURL(authUrl: "https://example.test/oauth")),
        )
        let api = makeAPI(transport)
        let vm = IntegrationsViewModel(oauth: FakeOAuth(error: OAuthError.userCancelled))
        await vm.connectGoogle(api: api)
        XCTAssertEqual(vm.statusMessage, "Google sign-in cancelled.")
        XCTAssertFalse(vm.googleConnected)
    }

    func testConnectGoogle503BranchSetsMessage() async {
        let transport = FakeTransport()
        transport.enqueue(
            path: "/integrations/google-calendar/connect",
            data: Data("backend says no".utf8),
            status: 503,
        )
        let api = makeAPI(transport)
        let vm = IntegrationsViewModel(oauth: FakeOAuth(error: nil))
        await vm.connectGoogle(api: api)
        XCTAssertTrue(vm.statusMessage?.contains("Google OAuth isn't configured") ?? false)
        XCTAssertFalse(vm.googleConnected)
    }

    func testConnectGoogleGenericErrorSetsCouldntConnectMessage() async throws {
        let transport = FakeTransport()
        try transport.enqueue(
            path: "/integrations/google-calendar/connect",
            data: BackendAPI.encoder.encode(OAuthConnectURL(authUrl: "https://example.test/oauth")),
        )
        let api = makeAPI(transport)
        let vm = IntegrationsViewModel(oauth: FakeOAuth(error: NSError(
            domain: "x",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "boom"],
        )))
        await vm.connectGoogle(api: api)
        XCTAssertTrue(vm.statusMessage?.contains("Couldn't connect Google") ?? false)
    }

    func testConnectOutlookSuccessRefreshes() async throws {
        let transport = FakeTransport()
        try transport.enqueue(
            path: "/integrations/outlook/connect",
            data: BackendAPI.encoder.encode(OAuthConnectURL(authUrl: "https://example.test/oauth")),
        )
        try transport.enqueue(
            path: "/integrations",
            data: BackendAPI.encoder.encode([IntegrationStatus(provider: "outlook", connected: true, expiresAt: nil)]),
        )
        let api = makeAPI(transport)
        let vm = IntegrationsViewModel(oauth: FakeOAuth(error: nil))
        await vm.connectOutlook(api: api)
        XCTAssertTrue(vm.outlookConnected)
        XCTAssertNil(vm.statusMessage)
    }

    func testConnectOutlookInvalidAuthURLSetsStatus() async throws {
        let transport = FakeTransport()
        try transport.enqueue(
            path: "/integrations/outlook/connect",
            data: BackendAPI.encoder.encode(OAuthConnectURL(authUrl: "")),
        )
        let api = makeAPI(transport)
        let vm = IntegrationsViewModel(oauth: FakeOAuth(error: nil))
        await vm.connectOutlook(api: api)
        XCTAssertEqual(vm.statusMessage, "Backend returned an invalid auth URL.")
    }

    func testConnectOutlookUserCancelledSetsStatus() async throws {
        let transport = FakeTransport()
        try transport.enqueue(
            path: "/integrations/outlook/connect",
            data: BackendAPI.encoder.encode(OAuthConnectURL(authUrl: "https://example.test/oauth")),
        )
        let api = makeAPI(transport)
        let vm = IntegrationsViewModel(oauth: FakeOAuth(error: OAuthError.userCancelled))
        await vm.connectOutlook(api: api)
        XCTAssertEqual(vm.statusMessage, "Outlook sign-in cancelled.")
    }

    func testConnectOutlook501BranchSetsComingSoon() async {
        let transport = FakeTransport()
        transport.enqueue(path: "/integrations/outlook/connect", data: Data("not implemented".utf8), status: 501)
        let api = makeAPI(transport)
        let vm = IntegrationsViewModel(oauth: FakeOAuth(error: nil))
        await vm.connectOutlook(api: api)
        XCTAssertEqual(vm.statusMessage, "Outlook integration coming soon.")
    }

    func testConnectOutlookGenericErrorSetsCouldntConnect() async throws {
        let transport = FakeTransport()
        try transport.enqueue(
            path: "/integrations/outlook/connect",
            data: BackendAPI.encoder.encode(OAuthConnectURL(authUrl: "https://example.test/oauth")),
        )
        let api = makeAPI(transport)
        let vm = IntegrationsViewModel(oauth: FakeOAuth(error: NSError(
            domain: "x",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "boom"],
        )))
        await vm.connectOutlook(api: api)
        XCTAssertTrue(vm.statusMessage?.contains("Couldn't connect Outlook") ?? false)
    }

    func testRefreshIntegrationsSilentlySwallowsListError() async {
        let transport = FakeTransport()
        transport.responseStatus = 500
        let api = makeAPI(transport)
        let vm = IntegrationsViewModel()
        await vm.refreshIntegrations(api: api)
        XCTAssertFalse(vm.googleConnected)
        XCTAssertFalse(vm.outlookConnected)
        XCTAssertNil(vm.statusMessage, "list-integrations error must NOT surface a status message")
    }

    /// requestCalendar() calls EKEventStore.requestFullAccessToEvents which prompts the user. In the test bundle this returns false (no permission UI), so we just verify the call returns without crashing and that appleCalendarGranted ends up false.
    func testRequestCalendarReturnsWithoutPermission() async {
        let vm = IntegrationsViewModel()
        await vm.requestCalendar()
        XCTAssertFalse(vm.appleCalendarGranted)
    }

    func testRefreshIntegrationsSetsBothConnectedFlagsFromList() async throws {
        let transport = FakeTransport()
        let providers = [
            IntegrationStatus(provider: "google", connected: true, expiresAt: nil),
            IntegrationStatus(provider: "outlook", connected: false, expiresAt: nil),
        ]
        transport.responseData = try BackendAPI.encoder.encode(providers)
        let api = makeAPI(transport)
        let vm = IntegrationsViewModel()
        await vm.refreshIntegrations(api: api)
        XCTAssertTrue(vm.googleConnected)
        XCTAssertFalse(vm.outlookConnected)
    }
}
