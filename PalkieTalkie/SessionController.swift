import Foundation
import Observation
import OSLog
import SwiftUI

private let signposter = OSSignposter(subsystem: "com.palkietalkie", category: "conversation")
private let logger = Logger(subsystem: "com.palkietalkie", category: "conversation")

/// Orchestrator and phase machine. Delegates audio, networking, persistence, and context-gathering to injectable
/// collaborators so the controller stays unit-testable.
protocol ContextGathering: Sendable {
    func gather() async -> ConversationContext
}

extension ContextGatherer: ContextGathering {}

/// Slice of `BackendAPI` the controller needs. Defining it as a protocol lets `SessionControllerTests` stub start / end
/// without standing up the transport.
protocol ConversationBackend: Sendable {
    func startConversation(
        personaId: String,
        context: ConversationContext,
        topicOverride: String?
    ) async throws -> StartResponse
    func endConversation(sessionId: String) async throws -> EndResponse
    func appendTranscript(sessionId: String, speaker: String, text: String, startedAt: Date, endedAt: Date) async throws
    func recordColdStart(
        durationMs: Int,
        phaseTimings: ColdStartTimings,
        sessionId: String
    ) async throws
    func getPersonas(search: String?, sort: String) async throws -> [PersonaDTO]
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

/// Factory for the audio streamer. Production returns a real `AudioStreamer` and starts it; tests return a fake that
/// records `playOutput` calls.
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

/// Factory for the PersonaPlex lifecycle. Returns a session that's ready to `open(wsUrl:)`. Tests inject a fake to
/// assert open/close flow.
protocol PersonaPlexSessionFactory: Sendable {
    func makeSession() -> PersonaPlexSessionType
}

struct DefaultPersonaPlexSessionFactory: PersonaPlexSessionFactory {
    func makeSession() -> PersonaPlexSessionType {
        PersonaPlexSession()
    }
}

/// Factory for the OpenAI Realtime client. Separate from `PersonaPlexSessionFactory` so the orchestrator wiring stays
/// explicit per provider.
protocol OpenAIRealtimeClientFactory: Sendable {
    func makeClient(instructions: String?) -> RealtimeClient
}

struct DefaultOpenAIRealtimeClientFactory: OpenAIRealtimeClientFactory {
    func makeClient(instructions: String?) -> RealtimeClient {
        OpenAIRealtimeClient(instructions: instructions)
    }
}

@MainActor
@Observable
final class SessionController {
    enum Phase: Equatable {
        case idle
        case gatheringContext
        case startingSession
        case connecting
        case live
        case ending
        case error(String)
    }

    var phase: Phase = .idle
    var transcript: [TranscriptChunk] = []
    // Persisted across app launches. Reads from UserDefaults on first access, writes through on every set. Default
    // empty → `resolvePersonaIdIfNeeded()` picks the first curated preset the first time. After that, the user's choice
    // from `PersonaPickerView` survives kill-and-relaunch.
    private static let lastPersonaKey = "lastSelectedPersonaId"
    var selectedPersonaId: String = UserDefaults.standard.string(forKey: SessionController.lastPersonaKey) ?? "" {
        didSet { UserDefaults.standard.set(selectedPersonaId, forKey: Self.lastPersonaKey) }
    }

    var startContextOverride: String?

    // MARK: - Collaborators (DI seams)

    private let context: ContextGathering
    private let backend: ConversationBackend
    private let micPermission: MicrophonePermissionRequesting
    private let streamerFactory: AudioStreamerFactory
    private let sessionFactory: PersonaPlexSessionFactory
    private let openAIFactory: OpenAIRealtimeClientFactory

    // MARK: - Live state

    private var audioStreamer: AudioStreamerType?
    private var personaPlex: PersonaPlexSessionType?
    private var openAIClient: RealtimeClient?
    private var pump: AudioPump?
    private var sessionStartedAt: Date?
    private var serverSessionId: String?
    private var observerTasks: [Task<Void, Never>] = []

    /// In-progress turn buffer. Stream emissions from the same speaker accumulate here; flush as one `transcripts` row
    /// on speaker switch or session end. Per CLAUDE.md, a transcripts row = one TURN, not one realtime-stream fragment.
    private struct TurnBuffer {
        let speaker: TranscriptChunk.Speaker
        var text: String
        let startedAt: Date
    }

    private var pendingTurn: TurnBuffer?

    init(
        context: ContextGathering = ContextGatherer.shared,
        backend: ConversationBackend = BackendAPI.shared,
        micPermission: MicrophonePermissionRequesting = DefaultMicrophonePermission(),
        streamerFactory: AudioStreamerFactory = DefaultAudioStreamerFactory(),
        sessionFactory: PersonaPlexSessionFactory = DefaultPersonaPlexSessionFactory(),
        openAIFactory: OpenAIRealtimeClientFactory = DefaultOpenAIRealtimeClientFactory()
    ) {
        self.context = context
        self.backend = backend
        self.micPermission = micPermission
        self.streamerFactory = streamerFactory
        self.sessionFactory = sessionFactory
        self.openAIFactory = openAIFactory
    }

    private func resolvePersonaIdIfNeeded() async throws -> Bool {
        if UUID(uuidString: selectedPersonaId) != nil { return true }
        return try await pickFirstPersonaFromServer()
    }

    /// Pulls /personas and pins selectedPersonaId to the first preset. Called when nothing is cached, and when /start
    /// 404s on the cached UUID (user-created persona deleted, dev DB reset, preset list rotated → UUID5 changed).
    private func pickFirstPersonaFromServer() async throws -> Bool {
        let personas = try await backend.getPersonas(search: nil, sort: "recommended")
        let resolved =
            personas.first(where: { $0.isPreset })
                ?? personas.first
        guard let resolved else { return false }
        selectedPersonaId = resolved.id
        return true
    }

    func start() async {
        let t0 = Date()
        phase = .gatheringContext
        let gatherInterval = signposter.beginInterval("conversation.gatherContext")
        let gathered = await context.gather()
        signposter.endInterval("conversation.gatherContext", gatherInterval)
        let tGatherEnd = Date()

        phase = .startingSession
        do {
            try await micPermission.requestMicrophonePermission()
            guard try await resolvePersonaIdIfNeeded() else {
                // No personas yet (backend still seeding, dev hiccup, etc). Stay idle silently — never block the user
                // with a scary error.
                phase = .idle
                return
            }
            let startInterval = signposter.beginInterval("conversation.backendStart")
            let response: StartResponse
            do {
                response = try await backend.startConversation(
                    personaId: selectedPersonaId,
                    context: gathered,
                    topicOverride: startContextOverride
                )
            } catch let BackendError.http(404, _) {
                // Cached persona ID is stale (user-created persona deleted, DB reset, preset list rotated). Re-resolve
                // from /personas and retry once.
                logger.info("conversation/start 404 — refreshing persona from server")
                guard try await pickFirstPersonaFromServer() else {
                    phase = .idle
                    return
                }
                response = try await backend.startConversation(
                    personaId: selectedPersonaId,
                    context: gathered,
                    topicOverride: startContextOverride
                )
            }
            signposter.endInterval("conversation.backendStart", startInterval)
            let tStartEnd = Date()
            serverSessionId = response.sessionId
            // BUILD-2026-05-25-A diagnostic — confirm latest binary on device and trace which path /start returns.
            logger
                .error(
                    "/start returned: provider=\(response.provider, privacy: .public) wsUrl=\(response.wsUrl, privacy: .public) tokenLen=\(response.ephemeralToken?.count ?? 0, privacy: .public)"
                )

            phase = .connecting
            let connectInterval = signposter.beginInterval("conversation.websocketConnect")
            let realtime: RealtimeClient
            if response.provider == "openai" {
                let client = openAIFactory.makeClient(instructions: response.textPrompt)
                try await client.open(wsUrl: response.wsUrl, ephemeralToken: response.ephemeralToken)
                openAIClient = client
                realtime = client
            } else {
                let session = sessionFactory.makeSession()
                // Backend bakes an HMAC ticket into response.wsUrl. Open it as-is.
                try await session.open(wsUrl: response.wsUrl)
                personaPlex = session
                realtime = session
            }
            signposter.endInterval("conversation.websocketConnect", connectInterval)

            // Wait for the server's ready signal before pumping audio. PersonaPlex: `\x00` handshake byte (server's
            // recv_loop only starts after step_system_prompts_async, ~30s on cold start). OpenAI: session.created
            // event. In both cases, sending audio earlier means dropped frames.
            await realtime.waitForServerReady()
            let tConnectEnd = Date()

            let streamer = try await streamerFactory.makeStreamer()
            audioStreamer = streamer

            sessionStartedAt = Date()
            phase = .live
            await startObserversForRealtime(client: realtime)
            let pump = AudioPump()
            if response.provider == "openai", let pcmStreamer = streamer as? PCM16AudioStreamerType {
                logger.error("audio pump → startPCM16 (OpenAI)")
                await pump.startPCM16(streamer: pcmStreamer, client: realtime)
            } else if let pSession = realtime as? PersonaPlexSessionType {
                logger.error("audio pump → start (PersonaPlex)")
                await pump.start(streamer: streamer, session: pSession)
            } else {
                logger
                    .error(
                        "audio pump → NO MATCH provider=\(response.provider, privacy: .public) streamerIsPCM16=\(streamer is PCM16AudioStreamerType, privacy: .public) realtimeIsPersonaPlex=\(realtime is PersonaPlexSessionType, privacy: .public)"
                    )
            }
            self.pump = pump

            // Cold-start telemetry: time from start() until the first inbound audio chunk lands. Posted to backend
            // /events for percentile tracking across users — confirms the "5-8s hidden by tips" target.
            let inboundAudio = await realtime.inboundAudio
            ColdStartReporter.scheduleReport(
                backend: backend,
                inboundAudio: inboundAudio,
                sessionId: response.sessionId,
                t0: t0,
                tGatherEnd: tGatherEnd,
                tStartEnd: tStartEnd,
                tConnectEnd: tConnectEnd
            )
        } catch {
            let message = String(describing: error)
            logger.error("conversation start failed: \(message, privacy: .public)")
            phase = .error(message)
            await teardown()
        }
        // Consume the override exactly once — next session should fall back to normal context.
        startContextOverride = nil
    }

    // Cold-start telemetry moved to `ColdStartReporter.swift` so the orchestrator stays focused on phase machine +
    // collaborator wiring.

    func end() async {
        phase = .ending
        // Flush any in-progress turn buffer before tearing down so the last utterance lands in transcripts. Without
        // this, the final turn (often the AI's closing line, or whatever the user said before tapping end) is lost.
        flushPendingTurn(endedAt: Date())
        let id = serverSessionId
        if let id {
            _ = try? await backend.endConversation(sessionId: id)
        }
        await teardown()
        phase = .idle
    }

    private func startObservers(session: PersonaPlexSessionType) async {
        let transcriptStream = await session.transcript
        let errorStream = await session.errors
        let transcriptTask = Task { [weak self] in
            for await chunk in transcriptStream {
                await MainActor.run {
                    self?.appendTranscript(chunk)
                }
            }
        }
        let errorTask = Task { [weak self] in
            for await message in errorStream {
                logger.error("personaplex stream error: \(message, privacy: .public)")
                await MainActor.run {
                    self?.phase = .error(message)
                }
            }
        }
        observerTasks = [transcriptTask, errorTask]
    }

    private func startObserversForRealtime(client: RealtimeClient) async {
        let transcriptStream = await client.transcript
        let errorStream = await client.errors
        let transcriptTask = Task { [weak self] in
            for await chunk in transcriptStream {
                await MainActor.run {
                    self?.appendTranscript(chunk)
                }
            }
        }
        let errorTask = Task { [weak self] in
            for await message in errorStream {
                logger.error("realtime stream error: \(message, privacy: .public)")
                await MainActor.run {
                    self?.phase = .error(message)
                }
            }
        }
        observerTasks = [transcriptTask, errorTask]
    }

    private func appendTranscript(_ chunk: TranscriptChunk) {
        transcript.append(chunk)
        // Aggregate stream fragments into turn rows. Speaker switch (or session end) flushes the in-flight buffer as
        // one POST → one DB row. Fragments from the same speaker join into one turn's text.
        if let pending = pendingTurn, pending.speaker == chunk.speaker {
            pendingTurn?.text += chunk.text
        } else {
            flushPendingTurn(endedAt: chunk.timestamp)
            pendingTurn = TurnBuffer(speaker: chunk.speaker, text: chunk.text, startedAt: chunk.timestamp)
        }
    }

    /// POSTs the in-flight turn buffer as one transcripts row. Called on speaker switch and on session end.
    /// Fire-and-forget: dropped POST = a missing turn row, not a corrupted one.
    private func flushPendingTurn(endedAt: Date) {
        guard let pending = pendingTurn, let sessionId = serverSessionId else { return }
        pendingTurn = nil
        let backend = backend
        Task {
            try? await backend.appendTranscript(
                sessionId: sessionId,
                speaker: pending.speaker.rawValue,
                text: pending.text,
                startedAt: pending.startedAt,
                endedAt: endedAt
            )
        }
    }

    private func teardown() async {
        for task in observerTasks {
            task.cancel()
        }
        observerTasks.removeAll()
        if let pump {
            await pump.stop()
        }
        pump = nil
        if let session = personaPlex {
            await session.close()
        }
        personaPlex = nil
        if let openAIClient {
            await openAIClient.close()
        }
        openAIClient = nil
        if let streamer = audioStreamer as? AudioStreamer {
            await streamer.stop()
        }
        audioStreamer = nil
        serverSessionId = nil
        sessionStartedAt = nil
        pendingTurn = nil
    }
}
