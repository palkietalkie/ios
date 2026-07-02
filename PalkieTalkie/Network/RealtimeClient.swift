import Foundation

/// Provider-agnostic realtime client surface. Both `PersonaPlexSession` (binary Ogg-Opus frames over WS to Modal) and `OpenAIWebRTCClient` (Opus media over WebRTC to OpenAI, JSON events on a data channel) conform to this.
///
/// Audio is provider-specific: PersonaPlex pushes/pulls wrapped Ogg-Opus pages through `send(audio:)` / `inboundAudio`, while the OpenAI WebRTC client carries media on its own peer connection and leaves those byte methods as no-ops. `SessionController` keeps the audio path provider-aware via the protocol implementation; the orchestrator itself only sees the unified surface.
protocol RealtimeClient: AnyObject, Sendable {
    func open(wsUrl: String, ephemeralToken: String?) async throws
    func close() async
    func send(audio chunk: Data) async throws

    /// Resolves once the underlying transport has signalled "ready for audio." For PersonaPlex this is the `\x00` server handshake byte; for OpenAI Realtime this resolves immediately after `session.update` is acknowledged (or right after WS upgrade since the server is always warm).
    func waitForServerReady() async

    var inboundAudio: AsyncStream<Data> { get async }
    var transcript: AsyncStream<TranscriptChunk> { get async }
    var errors: AsyncStream<String> { get async }
    /// Emits the error description when the transport dies UNEXPECTEDLY — the recv loop caught a socket/network error (e.g. NSPOSIXErrorDomain 57 "Socket is not connected", NSURLErrorDomain -1009 offline), as opposed to a clean `close()`. SessionController treats this as RECOVERABLE and reconnects, unlike `errors` (server-side app errors) which are terminal. NWPathMonitor alone misses this: a wifi→cellular handoff drops the socket while the path stays "online". Default is a no-op stream for providers/doubles that don't surface it.
    var disconnected: AsyncStream<String> { get async }
    /// Emits when the server reports the user has started speaking — iOS should stop playing queued AI audio so the cancellation feels immediate. PersonaPlex handles barge-in server-side via Inner Monologue (its WS just stops sending audio frames); for that path this stream is silent.
    var bargeIn: AsyncStream<Void> { get async }

    /// Inject a system hint into the live conversation and trigger the AI to respond. Used by the free-cap wrap-up: ~30s before the user's daily/weekly limit hits, SessionController asks the AI to wind down naturally. Best-effort and no-op for providers that don't support text injection (PersonaPlex today).
    func injectSystemHint(_ text: String) async

    /// Emits when the model invokes a recall tool mid-conversation (OpenAI function calling). SessionController fulfills each call against the backend and feeds the result back via `submitToolOutput`, asynchronously, so audio never blocks. PersonaPlex has no function calling — it uses the default empty stream.
    var toolCalls: AsyncStream<ToolCall> { get async }

    /// Return a tool's result to the model (function_call_output) and let it continue. No-op on providers without tools.
    func submitToolOutput(callId: String, output: String) async

    /// Cumulative realtime token usage for the session so far, summed from the provider's usage reports (OpenAI `response.done`). SessionController reads this at session end and reports it to the backend for cost analysis. Zero for providers that don't expose token usage (PersonaPlex bills through Modal).
    var usage: RealtimeUsage { get async }

    /// Live tutor output amplitude (0…1) for the Talk-view waveform, read synchronously per frame. The WS/PersonaPlex paths measure it in the AudioStreamer; the WebRTC path (which bypasses AudioStreamer) surfaces it here from its own inbound-audio stats. Default 0 for doubles / providers that don't measure it.
    var outputLevel: Float { get }
}

/// Summed realtime token usage across one session (OpenAI `response.done.usage`). Reported to the backend at session end; the backend stores it on the session row.
struct RealtimeUsage: Equatable {
    var inputTokens: Int
    var outputTokens: Int
    static let zero = RealtimeUsage(inputTokens: 0, outputTokens: 0)
}

/// A tool/function call the realtime model wants the client to fulfill during the conversation.
struct ToolCall {
    let callId: String
    let name: String
    let query: String
}

/// One turn of conversation text — provider-agnostic, emitted by every RealtimeClient's `transcript` stream and rendered by CaptionsView. Lives with the protocol (not a provider file) because both PersonaPlex and OpenAI produce it.
struct TranscriptChunk: Identifiable {
    let id: UUID
    enum Speaker: String { case user, persona }
    let speaker: Speaker
    let text: String
    let timestamp: Date

    init(speaker: Speaker, text: String, timestamp: Date = Date()) {
        id = UUID()
        self.speaker = speaker
        self.text = text
        self.timestamp = timestamp
    }
}

/// Defaults so providers without function calling (PersonaPlex) and test doubles don't each need to implement the tool surface. OpenAIWebRTCClient overrides both.
extension RealtimeClient {
    var disconnected: AsyncStream<String> {
        get async { AsyncStream { $0.finish() } }
    }

    var toolCalls: AsyncStream<ToolCall> {
        get async { AsyncStream { $0.finish() } }
    }

    func submitToolOutput(callId _: String, output _: String) async {}

    var usage: RealtimeUsage {
        get async { .zero }
    }

    var outputLevel: Float {
        0
    }
}
