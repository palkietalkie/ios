import Foundation

/// Provider-agnostic realtime client surface. Both `PersonaPlexSession` (binary Ogg-Opus frames over WS to Modal) and
/// `OpenAIRealtimeClient` (JSON event frames over WS to api.openai.com) conform to this.
///
/// The audio bytes flowing through `send(audio:)` and `inboundAudio` are protocol-specific (wrapped Ogg-Opus pages for
/// PersonaPlex, raw 24kHz mono PCM16 samples for OpenAI). `SessionController` keeps the audio path provider-aware via
/// the protocol implementation; the orchestrator itself only sees the unified surface.
protocol RealtimeClient: AnyObject, Sendable {
    func open(wsUrl: String, ephemeralToken: String?) async throws
    func close() async
    func send(audio chunk: Data) async throws

    /// Resolves once the underlying transport has signalled "ready for audio." For PersonaPlex this is the `\x00`
    /// server handshake byte; for OpenAI Realtime this resolves immediately after `session.update` is acknowledged (or
    /// right after WS upgrade since the server is always warm).
    func waitForServerReady() async

    var inboundAudio: AsyncStream<Data> { get async }
    var transcript: AsyncStream<TranscriptChunk> { get async }
    var errors: AsyncStream<String> { get async }
    /// Emits when the server reports the user has started speaking — iOS should stop playing queued AI audio so the
    /// cancellation feels immediate. PersonaPlex handles barge-in server-side via Inner Monologue (its WS just stops
    /// sending audio frames); for that path this stream is silent.
    var bargeIn: AsyncStream<Void> { get async }

    /// Inject a system hint into the live conversation and trigger the AI to respond. Used by the free-cap wrap-up: ~30s before the user's daily/weekly limit hits, SessionController asks the AI to wind down naturally. Best-effort and no-op for providers that don't support text injection (PersonaPlex today).
    func injectSystemHint(_ text: String) async
}
