@testable import PalkieTalkie
import XCTest

/// Smoke tests for the injectable-seam protocols + default impls in `SessionCollaborators.swift`. Default-impl construction is covered in `DefaultCollaboratorsTests` from the protocol-consumer side; this file pairs the source file so the CI test-pair check accepts the extraction.
final class SessionCollaboratorsTests: XCTestCase {
    func testConversationBackendExposesEmotionAndWebFetchTools() async throws {
        let fake = FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "s", textPrompt: "", voiceId: "", wsUrl: "wss://t",
                provider: "openai", ephemeralToken: "ek",
                freeSecondsRemaining: nil,
                freeLimitKind: nil,
            ),
            endResponse: EndResponse(sessionId: "s", durationSeconds: 0),
        )
        let backend: any ConversationBackend = fake
        try await backend.recordAIEmotions(sessionId: "s", laugh: 2, cheer: 0, gasp: 0, sigh: 0, groan: 0)
        let page = try await backend.webFetch(url: "https://x")
        XCTAssertEqual(page, "PAGE TEXT")
        XCTAssertEqual(fake.aiEmotionCalls.first?.laugh, 2)
    }

    /// `BackendAPI` must conform to `ConversationBackend` so SessionController can take either the real backend or a test fake interchangeably.
    func testBackendAPIConformsToConversationBackend() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://test.example.com"))
        // Authing is class-only (AnyObject) — use the existing test stub from BackendAPITests instead of re-defining here.
        let api: any ConversationBackend = BackendAPI(
            baseURL: baseURL,
            transport: URLSession.shared,
            auth: StubAuthing(),
        )
        _ = api
    }

    /// Production default `DefaultMicrophonePermission` must satisfy `MicrophonePermissionRequesting` so the production wiring in PalkieTalkieApp compiles.
    func testDefaultMicrophonePermissionConforms() {
        let perm: any MicrophonePermissionRequesting = DefaultMicrophonePermission()
        _ = perm
    }

    /// The default network monitor must actually emit a status — it backs SessionController's mid-call drop detection + auto-reconnect. A stream that never yields would leave the controller unable to notice a dropped path. Drain the first value (the monitor yields the current path status on start). Times out rather than hanging the suite if the stream is dead.
    func testDefaultNetworkPathMonitorEmitsInitialStatus() async {
        let monitor: any NetworkPathMonitoring = DefaultNetworkPathMonitor()
        let first = await withTaskGroup(of: Bool?.self) { group in
            group.addTask {
                for await status in monitor.statuses() {
                    return status
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
        XCTAssertNotNil(first, "DefaultNetworkPathMonitor must yield at least one path status within 3s")
    }

    /// The PersonaPlex session factory must produce a working session so SessionController's wiring compiles and runs. (OpenAI is constructed directly as a WebRTC client, no factory.)
    func testProviderFactoriesProduceClients() {
        let plex: any PersonaPlexSessionFactory = DefaultPersonaPlexSessionFactory()
        let session: PersonaPlexSessionType = plex.makeSession()
        _ = session
    }
}
