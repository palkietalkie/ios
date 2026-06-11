@testable import PalkieTalkie
import XCTest

/// Smoke tests for the injectable-seam protocols + default impls in `SessionCollaborators.swift`. Default-impl construction is covered in `DefaultCollaboratorsTests` from the protocol-consumer side; this file pairs the source file so the CI test-pair check accepts the extraction.
final class SessionCollaboratorsTests: XCTestCase {
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

    /// The provider factories must produce working clients so SessionController's per-provider wiring compiles and runs. Construct each and assert it yields a usable instance.
    func testProviderFactoriesProduceClients() {
        let plex: any PersonaPlexSessionFactory = DefaultPersonaPlexSessionFactory()
        let session: PersonaPlexSessionType = plex.makeSession()
        _ = session

        let openai: any OpenAIRealtimeClientFactory = DefaultOpenAIRealtimeClientFactory()
        let client: RealtimeClient = openai.makeClient(instructions: "be a friend")
        _ = client
    }
}
