import Foundation
@testable import PalkieTalkie
import XCTest

@MainActor
final class AppEnvironmentTests: XCTestCase {
    /// Production URLSession must NOT use `waitsForConnectivity = true`. With true, requests hang silently on flaky networks instead of erroring fast — and our UI relies on the warmup-tips screen reacting to fast errors, not stalling indefinitely. The comment in AppEnvironment.swift calls out this exact reason; this test pins it.
    func testProductionTransportDoesNotWaitForConnectivity() {
        let session = AppEnvironment.makeProductionTransport() as? URLSession
        XCTAssertNotNil(session, "expected URLSession transport")
        XCTAssertFalse(session?.configuration.waitsForConnectivity ?? true)
    }

    /// 15s/30s timeout budget is documented as deliberate (cold Clerk JWKS + Neon warmup tolerance vs. user-perceived hang). A regression to the URLSession defaults (60s / 7 days) would make "request taking forever" feel even worse. Pin both.
    func testProductionTransportTimeoutsMatchPolicy() {
        let session = AppEnvironment.makeProductionTransport() as? URLSession
        XCTAssertEqual(session?.configuration.timeoutIntervalForRequest, 15)
        XCTAssertEqual(session?.configuration.timeoutIntervalForResource, 30)
    }

    /// Factory builds a BackendAPI without throwing — catches the case where wiring up the Clerk adapter starts panicking at construction time (e.g. missing publishable key in test build).
    func testProductionBackendAPIBuildsWithoutThrowing() {
        let api: BackendAPI? = AppEnvironment.makeProductionBackendAPI()
        XCTAssertNotNil(api)
    }
}
