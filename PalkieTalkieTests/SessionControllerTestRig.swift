import Foundation
@testable import PalkieTalkie

/// Shared builder so the per-concern SessionController test files (Recall, AISpeaking, ServerReady) don't each duplicate the fake wiring. Mirrors the private makeController in SessionControllerTests; uses the shared fakes defined there.
@MainActor
func makeSessionControllerRig(
    session: FakePersonaPlexSession = FakePersonaPlexSession(),
    streamer: FakeAudioStreamer = FakeAudioStreamer(),
    serverReadyTimeout: Double? = nil,
) -> SessionControllerRig {
    let backend = FakeConversationBackend(
        startResponse: StartResponse(
            sessionId: "srv-1",
            textPrompt: "hi",
            voiceId: "v1",
            wsUrl: "wss://test",
            provider: "personaplex",
            ephemeralToken: nil,
        ),
        endResponse: EndResponse(sessionId: "srv-1", durationSeconds: 10),
    )
    let context = ConversationContext(
        localISOTime: "2025-01-01T00:00:00Z",
        timezone: "UTC",
        lat: 0,
        lon: 0,
        city: nil,
        weatherDescription: nil,
        temperatureC: nil,
        calendarEvents: [],
    )
    let pathMonitor = FakeNetworkPathMonitor()
    let controller = SessionController(
        context: FakeContextGatherer(context: context),
        backend: backend,
        micPermission: StubMicPermission(shouldThrow: false),
        streamerFactory: StubAudioStreamerFactory(streamer: streamer),
        sessionFactory: StubSessionFactory(session: session),
        serverReadyTimeoutOverride: serverReadyTimeout,
        pathMonitor: pathMonitor,
    )
    return SessionControllerRig(
        controller: controller, backend: backend, session: session, streamer: streamer, pathMonitor: pathMonitor,
    )
}
