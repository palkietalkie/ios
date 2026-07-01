import Foundation
import SwiftUI

/// SwiftUI environment plumbing for the constructor-injected `BackendAPI` and `Authing`. Replaces the old `BackendAPI.shared` / `ClerkAuth.shared` singletons — every view now reads via `@Environment` and `PalkieTalkieApp` is the single place where production wires the real `URLSession` + Clerk-backed adapter.
///
/// Test seam: `XCTest` cases construct their own `BackendAPI(transport: FakeTransport(...), auth: StubAuthing(...))` and attach it via `.environment(\.backendAPI, api)` on the view under test.
///
/// Single source of truth for the production URLSession config. Old code created a fresh URLSession inside `BackendAPI.init` whenever `transport` was nil — that defaulting is now lifted here so the dependency surface of BackendAPI stays narrow.
enum AppEnvironment {
    static func makeProductionTransport() -> any Transport {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        // Per-request STALL timeout: max time with zero bytes moving before the request errors. Raised to 30s because weak/congested networks (hotel wifi being the canonical case) can go quiet longer than 15s mid-request without being dead, and failing then shows a misleading "timed out" instead of completing. It doesn't slow the happy path (a healthy request never sits silent this long); the conversation-start latency budget is enforced via cold_start_complete telemetry + the warmup-tips UI, not by failing fast here.
        config.timeoutIntervalForRequest = 30
        // Resource timeout is the TOTAL wall-clock a single transfer may take (unlike the stall timeout above, and the only one a per-request `timeoutInterval` can NOT override). A multi-MB session-audio upload on a weak uplink legitimately runs minutes, so this ceiling is minutes; the old 30s guillotined long uploads mid-flight (the "model present, mic absent" sessions). Hot-path JSON is unaffected: it finishes in well under a second and never approaches this ceiling.
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }

    static func makeProductionBackendAPI() -> BackendAPI {
        BackendAPI(
            transport: makeProductionTransport(),
            auth: ClerkAuthAdapter(),
        )
    }

    static func makeProductionAnnouncer() -> any AuthAnnouncing {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "BACKEND_URL") as? String,
            let url = URL(string: urlString)
        else {
            fatalError("Info.plist BACKEND_URL is missing or unparseable — check project.yml settings.configs")
        }
        return BackendAuthAnnouncer(baseURL: url, auth: ClerkAuthAdapter())
    }

    static func makeProductionOnboardingAnnouncer() -> any OnboardingAnnouncing {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "BACKEND_URL") as? String,
            let url = URL(string: urlString)
        else {
            fatalError("Info.plist BACKEND_URL is missing or unparseable — check project.yml settings.configs")
        }
        return BackendOnboardingAnnouncer(baseURL: url, auth: ClerkAuthAdapter())
    }
}

extension EnvironmentValues {
    /// Backend API used by all views. Production: wired at app init with a real URLSession + Clerk adapter. Tests: override via `.environment(\.backendAPI, BackendAPI(transport: FakeTransport(), auth: StubAuthing()))`.
    @Entry var backendAPI: BackendAPI = AppEnvironment.makeProductionBackendAPI()

    /// Auth surface (user id, email, sign-out, JWT for backend calls). Same injection pattern as `backendAPI`.
    @Entry var authing: any Authing = ClerkAuthAdapter()

    /// Onboarding drop-off feed reporter. Defaults to a no-op so tests/previews never touch the network; PalkieTalkieApp injects the real one in production.
    @Entry var onboardingAnnouncer: any OnboardingAnnouncing = NoopOnboardingAnnouncer()
}
