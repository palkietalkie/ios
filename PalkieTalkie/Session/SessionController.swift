import Foundation
import Observation
import OSLog
import SwiftUI

private let signposter = OSSignposter(subsystem: "com.palkietalkie", category: "conversation")
private let logger = Logger(subsystem: "com.palkietalkie", category: "conversation")

/// Orchestrator and phase machine. Owns the conversation lifecycle: gather context → start session → connect WS → run audio loop → end. Delegates audio, networking, persistence, and context-gathering to the protocols declared in `SessionCollaborators.swift` so the controller stays unit-testable.
@MainActor
@Observable
final class SessionController {
    enum Phase: Equatable {
        case idle
        case gatheringContext
        case startingSession
        case connecting
        case live
        // Mid-call connectivity loss (elevator / tunnel). The dead session is torn down and we wait here for the path to return, then auto-restart — instead of leaving a frozen `.live` mic the user can't escape.
        case reconnecting
        case ending
        case error(String)
    }

    var phase: Phase = .idle
    /// Flipped true when the model calls the `end_conversation` tool (the user said goodbye). `MainTabView` watches this to leave the Talk tab; switching tabs makes `ConversationView` disappear, which tears the session down. Reset by the navigator after it acts.
    var endRequestedByTool = false
    /// Set true when the session ended because the user hit their free-plan time limit (not a tab switch or normal goodbye). ConversationView shows the "out of free time" screen with an upgrade CTA instead of going silently idle. Reset at the start of the next session.
    var endedOnFreeCapLimit = false
    /// Which cap was hit, "daily" or "weekly", so the limit screen says the right thing ("back tomorrow" vs the longer "back Monday"). nil until a cap actually ends a session.
    var freeCapLimitKind: String?
    /// True from a cap-end until the next start, even after the limit overlay is dismissed — so the Talk view keeps showing the last transcript (the user dismisses the overlay to read what they just said). Separate from `endedOnFreeCapLimit`, which only drives the overlay and clears on dismiss.
    var reviewLastTranscript = false
    var transcript: [TranscriptChunk] = []
    /// True while the tutor is actively speaking. Drives the mic's swell/glow animation in ConversationView. Set when an AI (`.persona`) transcript chunk arrives, cleared after a short gap with no new AI chunk. This is the conversation-level "is it the AI's turn" signal — distinct from `phase == .live`, which stays true for the whole session.
    var isAISpeaking: Bool = false
    var aiSpeakingResetTask: Task<Void, Never>?
    // Persisted across app launches. Reads from UserDefaults on first access, writes through on every set. Default empty → `resolvePersonaIdIfNeeded()` picks the first curated preset the first time. After that, the user's choice from `PersonaPickerView` survives kill-and-relaunch.
    private static let lastPersonaKey = "lastSelectedPersonaId"
    var selectedPersonaId: String = UserDefaults.standard.string(forKey: SessionController.lastPersonaKey) ?? "" {
        didSet { UserDefaults.standard.set(selectedPersonaId, forKey: Self.lastPersonaKey) }
    }

    var startContextOverride: String?

    // MARK: - Collaborators (DI seams)

    private let context: ContextGathering
    let backend: ConversationBackend
    private let micPermission: MicrophonePermissionRequesting
    private let streamerFactory: AudioStreamerFactory
    private let sessionFactory: PersonaPlexSessionFactory
    private let openAIFactory: OpenAIRealtimeClientFactory
    /// Test seam: forces the server-ready timeout (seconds) for both providers. nil in production, where OpenAI gets 20s and PersonaPlex 90s (cold start). Tests set a tiny value to exercise the timeout path without a 90s wait.
    private let serverReadyTimeoutOverride: Double?
    /// Internal (not private) so SessionController+NetworkRecovery.swift can reach it — same cross-file-extension reason as serverReadyContinuation.
    let pathMonitor: NetworkPathMonitoring

    // MARK: - Live state

    private var audioStreamer: AudioStreamerType?
    private var personaPlex: PersonaPlexSessionType?
    private var openAIClient: RealtimeClient?
    private var pump: AudioPump?
    private var sessionStartedAt: Date?
    var serverSessionId: String?
    /// Active provider for the current session ("openai" / "personaplex"), from /start. Both providers flow through startObserversForRealtime (PersonaPlex's session also conforms to RealtimeClient), so the provider can't be inferred from the observer path — it's recorded here for session-error reporting.
    var serverProvider: String?
    var observerTasks: [Task<Void, Never>] = []
    /// Tasks the controller scheduled to enforce the free-cap mid-session: one warns the AI to wrap up at ~30s remaining, the other hard-ends the session at 0s. Cancelled in teardown() so a manual end doesn't leave them pending. Internal (not private) so the free-cap timers in SessionController+FreeCap.swift can install them.
    var freeCapTasks: [Task<Void, Never>] = []
    /// Lives for the whole session (across reconnects), not per-WS — so it can still observe the path coming back after a drop. Started lazily by `start()`, cancelled only by `end()` (never by `teardown()`, which runs on every drop). Internal so the NetworkRecovery extension can manage it.
    var networkTask: Task<Void, Never>?

    /// In-progress turn buffer. Stream emissions from the same speaker accumulate here; flush as one `transcripts` row on speaker switch or session end. Per CLAUDE.md, a transcripts row = one TURN, not one realtime-stream fragment.
    /// Internal (not private) so the buffering logic in SessionController+Transcript.swift can read and flush it. Stored state must live on the type itself; only the behavior moves to the extension.
    struct TurnBuffer {
        let speaker: TranscriptChunk.Speaker
        var text: String
        let startedAt: Date
    }

    var pendingTurn: TurnBuffer?

    init(
        context: ContextGathering = ContextGatherer.shared,
        backend: ConversationBackend,
        micPermission: MicrophonePermissionRequesting = DefaultMicrophonePermission(),
        streamerFactory: AudioStreamerFactory = DefaultAudioStreamerFactory(),
        sessionFactory: PersonaPlexSessionFactory = DefaultPersonaPlexSessionFactory(),
        openAIFactory: OpenAIRealtimeClientFactory = DefaultOpenAIRealtimeClientFactory(),
        serverReadyTimeoutOverride: Double? = nil,
        pathMonitor: NetworkPathMonitoring = DefaultNetworkPathMonitor(),
    ) {
        self.context = context
        self.backend = backend
        self.micPermission = micPermission
        self.streamerFactory = streamerFactory
        self.sessionFactory = sessionFactory
        self.openAIFactory = openAIFactory
        self.serverReadyTimeoutOverride = serverReadyTimeoutOverride
        self.pathMonitor = pathMonitor
    }

    func start() async {
        startNetworkMonitoringIfNeeded()
        endedOnFreeCapLimit = false
        reviewLastTranscript = false
        freeCapLimitKind = nil
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
                // No personas yet (backend still seeding, dev hiccup, etc). Stay idle silently — never block the user with a scary error.
                phase = .idle
                return
            }
            let startInterval = signposter.beginInterval("conversation.backendStart")
            let response: StartResponse
            do {
                response = try await backend.startConversation(
                    personaId: selectedPersonaId,
                    context: gathered,
                    topicOverride: startContextOverride,
                )
            } catch BackendError.http(404, _) {
                // Cached persona ID is stale (user-created persona deleted, DB reset, preset list rotated). Re-resolve from /personas and retry once.
                logger.info("conversation/start 404 — refreshing persona from server")
                guard try await pickFirstPersonaFromServer() else {
                    phase = .idle
                    return
                }
                response = try await backend.startConversation(
                    personaId: selectedPersonaId,
                    context: gathered,
                    topicOverride: startContextOverride,
                )
            }
            signposter.endInterval("conversation.backendStart", startInterval)
            let tStartEnd = Date()
            serverSessionId = response.sessionId
            serverProvider = response.provider
            // BUILD-2026-05-25-A diagnostic — confirm latest binary on device and trace which path /start returns.
            logger
                .error(
                    "/start returned: provider=\(response.provider, privacy: .public) wsUrl=\(response.wsUrl, privacy: .public) tokenLen=\(response.ephemeralToken?.count ?? 0, privacy: .public)",
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

            // Wait for the server's ready signal before pumping audio — sending earlier drops frames. PersonaPlex emits a `\x00` handshake byte (its recv_loop only starts after step_system_prompts_async); OpenAI emits a session.created event.
            // Bounded so a never-arriving signal (dead WS after a persona switch, exhausted quota, cold-start crash) can't hang on "Loading your tutor…" forever; tests pass serverReadyTimeoutOverride to shorten it.
            // 20s for OpenAI: no cold start, session.created is sub-second, so this ceiling only trips on a genuine failure.
            // 90s for PersonaPlex: Modal scale-to-zero boots a container + loads weights to VRAM (~10-20s) then runs the first system-prompt pass (~15-30s), so a cold start legitimately reaches ~30-60s before the handshake byte.
            let readyTimeout = serverReadyTimeoutOverride ?? (response.provider == "openai" ? 20 : 90)
            guard await awaitServerReady(realtime, timeoutSeconds: readyTimeout) else {
                throw SessionStartError.serverReadyTimeout
            }
            let tConnectEnd = Date()

            let streamer = try await streamerFactory.makeStreamer()
            audioStreamer = streamer

            sessionStartedAt = Date()
            phase = .live
            await startObserversForRealtime(client: realtime)
            self.pump = await startAudioPump(streamer: streamer, realtime: realtime, provider: response.provider)

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
                tConnectEnd: tConnectEnd,
            )

            // Free-cap mid-session enforcement, driven by the precise seconds /start returned. nil (premium) schedules nothing.
            scheduleFreeCapWrapUp(
                realtime: realtime,
                freeSecondsRemaining: response.freeSecondsRemaining,
                freeLimitKind: response.freeLimitKind,
            )
        } catch {
            // Logs keep the full diagnostic; the UI shows the friendly message for errors that provide one (BackendError, SessionStartError), falling back to the raw describe otherwise.
            logger.error("conversation start failed: \(String(describing: error), privacy: .public)")
            let userMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            phase = .error(userMessage)
            await teardown()
        }
        // Consume the override exactly once — next session should fall back to normal context.
        startContextOverride = nil
    }

    /// Pick and start the provider-correct audio pump: OpenAI streams PCM16 both directions; PersonaPlex drives the Ogg-Opus session. Returns the started pump so the caller retains it for teardown.
    private func startAudioPump(
        streamer: AudioStreamerType, realtime: RealtimeClient, provider: String,
    ) async -> AudioPump {
        let pump = AudioPump()
        if provider == "openai", let pcmStreamer = streamer as? PCM16AudioStreamerType {
            logger.error("audio pump → startPCM16 (OpenAI)")
            await pump.startPCM16(streamer: pcmStreamer, client: realtime)
        } else if let pSession = realtime as? PersonaPlexSessionType {
            logger.error("audio pump → start (PersonaPlex)")
            await pump.start(streamer: streamer, session: pSession)
        } else {
            logger
                .error(
                    "audio pump → NO MATCH provider=\(provider, privacy: .public) streamerIsPCM16=\(streamer is PCM16AudioStreamerType, privacy: .public) realtimeIsPersonaPlex=\(realtime is PersonaPlexSessionType, privacy: .public)",
                )
        }
        return pump
    }

    /// One-shot continuation parked by `awaitServerReady` (in SessionController+ServerReady.swift). Lives on the @MainActor instance so the ready-task and the timeout-task resolve it without sharing a mutable local across `@Sendable` closures.
    var serverReadyContinuation: CheckedContinuation<Bool, Never>?

    // Cold-start telemetry moved to `ColdStartReporter.swift` so the orchestrator stays focused on phase machine + collaborator wiring.

    func end() async {
        // Explicit end (user left the Talk tab) — stop watching the path. A drop-driven teardown does NOT come through here, so the monitor keeps running to catch the path returning.
        cancelNetworkMonitoring()
        phase = .ending
        // Flush any in-progress turn buffer before tearing down so the last utterance lands in transcripts. Without this, the final turn (often the AI's closing line, or whatever the user said before tapping end) is lost.
        flushPendingTurn(endedAt: Date())
        let id = serverSessionId
        let streamer = audioStreamer
        if let id {
            if let streamer {
                if let range = await streamer.pitchTracker.range() {
                    _ = try? await backend.recordPitchRange(
                        sessionId: id, minHz: range.min, maxHz: range.max,
                    )
                }
                let counts = await streamer.emotionCounts()
                let laugh = counts["laugh"] ?? 0
                let cheer = counts["cheer"] ?? 0
                let gasp = counts["gasp"] ?? 0
                let sigh = counts["sigh"] ?? 0
                let groan = counts["groan"] ?? 0
                if laugh + cheer + gasp + sigh + groan > 0 {
                    _ = try? await backend.recordAIEmotions(
                        sessionId: id, laugh: laugh, cheer: cheer, gasp: gasp, sigh: sigh, groan: groan,
                    )
                }
            }
            // Read realtime token usage before teardown nils the client. Nil for PersonaPlex (no OpenAI usage) so the backend stores NULL, not a misleading 0.
            let usage = await openAIClient?.usage
            _ = try? await backend.endConversation(
                sessionId: id,
                inputTokens: usage?.inputTokens,
                outputTokens: usage?.outputTokens,
            )
        }
        await teardown()
        // Audio upload AFTER teardown so the wav file is closed/finalized. Best-effort: a failed upload doesn't reopen the session — we just lose retention for that session. File is deleted whether upload succeeded or not so we don't accumulate local copies.
        if let id, let streamer {
            await uploadMicAudioIfAny(sessionId: id, streamer: streamer)
        }
        phase = .idle
    }

    /// Internal (not private) so SessionController+NetworkRecovery.swift can tear a dropped session down before reconnecting.
    func teardown() async {
        aiSpeakingResetTask?.cancel()
        aiSpeakingResetTask = nil
        isAISpeaking = false
        for task in observerTasks {
            task.cancel()
        }
        observerTasks.removeAll()
        for task in freeCapTasks {
            task.cancel()
        }
        freeCapTasks.removeAll()
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
        if let streamer = audioStreamer {
            await streamer.stop()
        }
        audioStreamer = nil
        serverSessionId = nil
        serverProvider = nil
        sessionStartedAt = nil
        pendingTurn = nil
    }
}
