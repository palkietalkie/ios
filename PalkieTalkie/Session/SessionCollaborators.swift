import Foundation
import Network

/// Injectable seams that SessionController depends on. Production wires the real implementations declared below as `Default*`; tests inject fakes that drive the phase machine without standing up audio / network / Clerk. Splitting these out of SessionController.swift keeps the orchestrator file focused on the state machine; the protocol surface here is what tests target.
protocol ContextGathering: Sendable {
    func gather() async -> ConversationContext
}

extension ContextGatherer: ContextGathering {}

/// Slice of `BackendAPI` the controller needs. Defining it as a protocol lets `SessionControllerTests` stub start / end without standing up the transport.
protocol ConversationBackend: Sendable {
    func startConversation(
        personaId: String,
        context: ConversationContext,
        topicOverride: String?,
    ) async throws -> StartResponse
    func endConversation(sessionId: String, inputTokens: Int?, outputTokens: Int?) async throws
        -> EndResponse
    func appendTranscript(sessionId: String, speaker: String, text: String, startedAt: Date, endedAt: Date) async throws
    func recordColdStart(
        durationMs: Int,
        phaseTimings: ColdStartTimings,
        sessionId: String,
    ) async throws
    func recordPitchRange(sessionId: String, minHz: Float, maxHz: Float) async throws
    func recordAIEmotions(sessionId: String, laugh: Int, cheer: Int, gasp: Int, sigh: Int, groan: Int) async throws
    func recordSessionError(sessionId: String?, provider: String, reason: String) async throws
    func recordToolCall(sessionId: String?, name: String, query: String?) async throws
    func recordSessionEnd(sessionId: String, reason: String) async throws
    func uploadMicAudio(sessionId: String, deflatedWav: Data) async throws
    func uploadModelAudio(sessionId: String, deflatedWav: Data) async throws
    func getPersonas(search: String?, sort: String) async throws -> [PersonaDTO]
    func getEntitlement() async throws -> Entitlement
    // Conversation-time recall, invoked when the realtime model calls a tool. Each returns concise text for the model to read back.
    func recallFacts(query: String) async throws -> String
    func recallConversations(query: String) async throws -> String
    func searchTranscripts(query: String) async throws -> String
    /// Fetch a public URL's readable text so the model grounds itself in real facts instead of inventing them.
    func webFetch(url: String) async throws -> String
}

extension BackendAPI: ConversationBackend {}

/// Mic-permission seam — production calls `AudioSessionManager`; tests no-op.
protocol MicrophonePermissionRequesting: Sendable {
    func requestMicrophonePermission() async throws
}

struct DefaultMicrophonePermission: MicrophonePermissionRequesting {
    func requestMicrophonePermission() async throws {
        try await AudioSessionManager.requestMicrophonePermission()
    }
}

/// Factory for the audio streamer. Production returns a real `AudioStreamer` and starts it; tests return a fake that records `playOutput` calls.
protocol AudioStreamerFactory: Sendable {
    func makeStreamer() async throws -> AudioStreamerType
}

struct DefaultAudioStreamerFactory: AudioStreamerFactory {
    func makeStreamer() async throws -> AudioStreamerType {
        let streamer = AudioStreamer()
        try await streamer.start()
        return streamer
    }
}

/// Factory for the PersonaPlex lifecycle. Returns a session that's ready to `open(wsUrl:)`. Tests inject a fake to assert open/close flow.
protocol PersonaPlexSessionFactory: Sendable {
    func makeSession() -> PersonaPlexSessionType
}

struct DefaultPersonaPlexSessionFactory: PersonaPlexSessionFactory {
    func makeSession() -> PersonaPlexSessionType {
        PersonaPlexSession()
    }
}

/// Factory for the OpenAI Realtime client. Separate from `PersonaPlexSessionFactory` so the orchestrator wiring stays explicit per provider.
protocol OpenAIRealtimeClientFactory: Sendable {
    func makeClient(instructions: String?) -> RealtimeClient
}

struct DefaultOpenAIRealtimeClientFactory: OpenAIRealtimeClientFactory {
    func makeClient(instructions: String?) -> RealtimeClient {
        OpenAIRealtimeClient(instructions: instructions)
    }
}

/// Connectivity seam. Emits `true` when a usable network path exists and `false` when it's gone, starting with the current status. Backs SessionController's mid-call drop detection + auto-reconnect (elevator / tunnel / dead zone). Tests inject a fake to drive transitions deterministically without a real radio.
protocol NetworkPathMonitoring: Sendable {
    func statuses() -> AsyncStream<Bool>
}

struct DefaultNetworkPathMonitor: NetworkPathMonitoring {
    func statuses() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            monitor.start(queue: DispatchQueue(label: "com.palkietalkie.network-path"))
            continuation.onTermination = { _ in monitor.cancel() }
        }
    }
}
