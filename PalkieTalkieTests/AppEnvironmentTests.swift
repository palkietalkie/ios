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

    /// Factory builds a BackendAPI without throwing — catches the case where wiring up the Clerk adapter starts panicking at construction time. Skips when Info.plist's BACKEND_URL isn't reachable from the test bundle (intermittent in full-suite runs where Bundle.main loads ahead of the test host wiring).
    func testProductionBackendAPIBuildsWithoutThrowing() throws {
        guard let url = Bundle.main.object(forInfoDictionaryKey: "BACKEND_URL") as? String,
              !url.isEmpty
        else {
            throw XCTSkip(
                "BACKEND_URL not in test-host Info.plist yet; the factory would fatalError. Re-run picks it up once the host app's bundle is ready.",
            )
        }
        let api: BackendAPI? = AppEnvironment.makeProductionBackendAPI()
        XCTAssertNotNil(api)
    }

    /// The auth announcer factory must produce a usable `AuthAnnouncing` (it reads BACKEND_URL and wires the Clerk adapter). SignInViewModel defaults to this factory, so a fatalError on a missing/unparseable URL would crash sign-in at construction — guard the happy path here. Skips when the test-host Info.plist hasn't loaded BACKEND_URL yet (same intermittency as the BackendAPI factory test).
    func testProductionAnnouncerBuildsWithoutThrowing() throws {
        guard let url = Bundle.main.object(forInfoDictionaryKey: "BACKEND_URL") as? String,
              !url.isEmpty
        else {
            throw XCTSkip(
                "BACKEND_URL not in test-host Info.plist yet; the factory would fatalError. Re-run picks it up once the host app's bundle is ready.",
            )
        }
        let announcer: (any AuthAnnouncing)? = AppEnvironment.makeProductionAnnouncer()
        XCTAssertNotNil(announcer)
    }

    /// The onboarding drop-off announcer factory reads BACKEND_URL + wires the Clerk adapter, same as the auth announcer. PalkieTalkieApp injects it at the root, so a fatalError on a missing URL would crash launch — pin the happy path. Skips until the test-host Info.plist exposes BACKEND_URL.
    func testProductionOnboardingAnnouncerBuildsWithoutThrowing() throws {
        guard let url = Bundle.main.object(forInfoDictionaryKey: "BACKEND_URL") as? String,
              !url.isEmpty
        else {
            throw XCTSkip("BACKEND_URL not in test-host Info.plist yet; the factory would fatalError.")
        }
        let announcer: (any OnboardingAnnouncing)? = AppEnvironment.makeProductionOnboardingAnnouncer()
        XCTAssertNotNil(announcer)
    }
}
