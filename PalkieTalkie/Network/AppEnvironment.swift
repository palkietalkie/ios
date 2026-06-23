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
        // 15s tolerates cold Clerk JWKS fetch + Neon warmup on endpoints like /stats that aren't on the conversation-start hot path. Conversation-start latency budget (1.5s) is enforced via cold_start_complete telemetry, not by failing the request — failing here would just show the user a misleading "timed out" instead of letting the warmup tips UI run.
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
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
