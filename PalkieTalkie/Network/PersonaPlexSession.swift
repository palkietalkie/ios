import Foundation

/// Lifecycle protocol the orchestrator (`SessionController`) depends on. Lets us swap a fake session for
/// `SessionControllerTests` without spinning up a real WebSocket. Inherits from `RealtimeClient` so the orchestrator
/// can treat a PersonaPlex session as a generic realtime client when wiring cross-provider plumbing (cold-start
/// telemetry, observer streams).
protocol PersonaPlexSessionType: RealtimeClient {
    func open(wsUrl: String) async throws
    func send(control action: PersonaPlexClient.ControlAction) async throws
    func send(audio opusFrame: Data) async throws
}

/// Thin lifecycle wrapper around `PersonaPlexClient`. `SessionController` only sees this surface
/// (open/close/send-control + streams) so the orchestrator's dependency-injection seam is one protocol, not several.
actor PersonaPlexSession: PersonaPlexSessionType, RealtimeClient {
    private let client: PersonaPlexClient

    init(client: PersonaPlexClient = PersonaPlexClient()) {
        self.client = client
    }

    func open(wsUrl: String) async throws {
        try await client.connect(wsUrl: wsUrl)
    }

    /// RealtimeClient adapter — PersonaPlex doesn't use the ephemeral token (it bakes an HMAC ticket directly into
    /// wsUrl).
    func open(wsUrl: String, ephemeralToken _: String?) async throws {
        try await client.connect(wsUrl: wsUrl)
    }

    func close() async {
        await client.close()
    }

    func send(control action: PersonaPlexClient.ControlAction) async throws {
        try await client.sendControl(action)
    }

    func send(audio opusFrame: Data) async throws {
        try await client.sendAudio(opusFrame)
    }

    func waitForServerReady() async {
        await client.waitForServerHandshake()
    }

    var inboundAudio: AsyncStream<Data> {
        get async { await client.inboundAudio }
    }

    var transcript: AsyncStream<TranscriptChunk> {
        get async { await client.transcript }
    }

    var errors: AsyncStream<String> {
        get async { await client.errors }
    }

    var bargeIn: AsyncStream<Void> {
        // PersonaPlex handles barge-in server-side via Inner Monologue — the WS just stops sending audio frames the
        // moment user speech is detected, so iOS doesn't need to interrupt local playback. Return a finished stream.
        get async { AsyncStream<Void> { $0.finish() } }
    }

    /// PersonaPlex's wire protocol has no text-injection channel today; the wrap-up hint is a best-effort feature, so we no-op here. SessionController still hard-ends the session at the cap regardless.
    func injectSystemHint(_: String) async {}
}
