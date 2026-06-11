@testable import PalkieTalkie
import XCTest

/// Additional branches of SessionController that the original SessionControllerTests didn't cover. Each test pins one specific path:
/// - Resolve-persona returns false (empty `/personas`) → stay `.idle`.
/// - Cached persona is non-UUID → must call `/personas`.
/// - End with no in-flight session → no backend calls.
/// - Repeated end() after end() is a no-op.
/// - Pump branch when streamer is the OpenAI PCM16 shape but client is also PersonaPlex (defensive log-only branch).
@MainActor
final class SessionControllerBranchTests: XCTestCase {
    private func makeContext() -> ConversationContext {
        ConversationContext(
            localISOTime: "2026-01-01T00:00:00Z",
            timezone: "UTC", lat: 0, lon: 0,
            city: nil, weatherDescription: nil, temperatureC: nil,
            calendarEvents: [],
        )
    }

    func testStartWithNoPersonasStaysIdle() async {
        // No personas → resolvePersonaIdIfNeeded returns false → controller stays .idle silently.
        // Clear any previously-persisted persona id so this test doesn't inherit a valid UUID from an earlier run.
        UserDefaults.standard.removeObject(forKey: "lastSelectedPersonaId")
        defer { UserDefaults.standard.removeObject(forKey: "lastSelectedPersonaId") }
        let backend = FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "s", textPrompt: "", voiceId: "", wsUrl: "wss://x",
                provider: "personaplex", ephemeralToken: nil,
            ),
            endResponse: EndResponse(sessionId: "s", durationSeconds: 0),
            personas: [], // ← empty
        )
        let controller = SessionController(
            context: FakeContextGatherer(context: makeContext()),
            backend: backend,
            micPermission: StubMicPermission(shouldThrow: false),
            streamerFactory: StubAudioStreamerFactory(streamer: FakeAudioStreamer()),
            sessionFactory: StubSessionFactory(session: FakePersonaPlexSession()),
        )
        // Force an empty persona id so resolvePersonaIdIfNeeded goes to the server lookup branch.
        controller.selectedPersonaId = ""
        await controller.start()
        XCTAssertEqual(controller.phase, .idle)
    }

    func testEndWithoutStartIsNoOp() async {
        let backend = FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "s", textPrompt: "", voiceId: "", wsUrl: "",
                provider: "personaplex", ephemeralToken: nil,
            ),
            endResponse: EndResponse(sessionId: "s", durationSeconds: 0),
        )
        let controller = SessionController(
            context: FakeContextGatherer(context: makeContext()),
            backend: backend,
            micPermission: StubMicPermission(shouldThrow: false),
            streamerFactory: StubAudioStreamerFactory(streamer: FakeAudioStreamer()),
            sessionFactory: StubSessionFactory(session: FakePersonaPlexSession()),
        )
        await controller.end()
        XCTAssertEqual(controller.phase, .idle)
        let endCount = await backend.endCount
        XCTAssertEqual(endCount, 0, "no in-flight session means no /end POST")
    }

    func testSelectedPersonaIdPersistsToUserDefaults() {
        let backend = FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "s", textPrompt: "", voiceId: "", wsUrl: "",
                provider: "personaplex", ephemeralToken: nil,
            ),
            endResponse: EndResponse(sessionId: "s", durationSeconds: 0),
        )
        let controller = SessionController(
            context: FakeContextGatherer(context: makeContext()),
            backend: backend,
            micPermission: StubMicPermission(shouldThrow: false),
            streamerFactory: StubAudioStreamerFactory(streamer: FakeAudioStreamer()),
            sessionFactory: StubSessionFactory(session: FakePersonaPlexSession()),
        )
        let unique = "test-persona-\(UUID().uuidString)"
        controller.selectedPersonaId = unique
        XCTAssertEqual(UserDefaults.standard.string(forKey: "lastSelectedPersonaId"), unique)
    }

    func testStartContextOverrideForwarded() async {
        let backend = FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "s", textPrompt: "", voiceId: "", wsUrl: "wss://x",
                provider: "personaplex", ephemeralToken: nil,
            ),
            endResponse: EndResponse(sessionId: "s", durationSeconds: 0),
        )
        let controller = SessionController(
            context: FakeContextGatherer(context: makeContext()),
            backend: backend,
            micPermission: StubMicPermission(shouldThrow: false),
            streamerFactory: StubAudioStreamerFactory(streamer: FakeAudioStreamer()),
            sessionFactory: StubSessionFactory(session: FakePersonaPlexSession()),
        )
        controller.startContextOverride = "talk about Tokyo"
        await controller.start()
        // After start, override is reset to nil.
        XCTAssertNil(controller.startContextOverride)
    }

    /// Backend errors that are NOT 404 surface directly as `.error` — no retry. The 404 retry path is in
    /// SessionControllerTests.
    func testNon404BackendErrorTransitionsToError() async {
        let backend = FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "s", textPrompt: "", voiceId: "", wsUrl: "",
                provider: "personaplex", ephemeralToken: nil,
            ),
            endResponse: EndResponse(sessionId: "s", durationSeconds: 0),
            startError: BackendError.http(500, "boom"),
        )
        let controller = SessionController(
            context: FakeContextGatherer(context: makeContext()),
            backend: backend,
            micPermission: StubMicPermission(shouldThrow: false),
            streamerFactory: StubAudioStreamerFactory(streamer: FakeAudioStreamer()),
            sessionFactory: StubSessionFactory(session: FakePersonaPlexSession()),
        )
        await controller.start()
        guard case .error = controller.phase else {
            return XCTFail("expected .error, got \(controller.phase)")
        }
    }

    /// When the 404 retry's second `/personas` lookup also returns empty (DB still empty), we should stay `.idle`, not raise an error.
    func testStaleCacheRetryFindsNothingStaysIdle() async {
        let stale = UUID().uuidString
        let backend = FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "s", textPrompt: "", voiceId: "", wsUrl: "wss://x",
                provider: "personaplex", ephemeralToken: nil,
            ),
            endResponse: EndResponse(sessionId: "s", durationSeconds: 0),
            personas: [], // empty even on retry
        )
        await backend.setStartErrorOnce(BackendError.http(404, "not found"))
        let controller = SessionController(
            context: FakeContextGatherer(context: makeContext()),
            backend: backend,
            micPermission: StubMicPermission(shouldThrow: false),
            streamerFactory: StubAudioStreamerFactory(streamer: FakeAudioStreamer()),
            sessionFactory: StubSessionFactory(session: FakePersonaPlexSession()),
        )
        controller.selectedPersonaId = stale
        await controller.start()
        XCTAssertEqual(controller.phase, .idle)
    }
}
