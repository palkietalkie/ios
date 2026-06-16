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
    private var serverSessionId: String?
    private var observerTasks: [Task<Void, Never>] = []
    /// Tasks the controller scheduled to enforce the free-cap mid-session: one warns the AI to wrap up at ~30s remaining, the other hard-ends the session at 0s. Cancelled in teardown() so a manual end doesn't leave them pending.
    private var freeCapTasks: [Task<Void, Never>] = []
    /// Lives for the whole session (across reconnects), not per-WS — so it can still observe the path coming back after a drop. Started lazily by `start()`, cancelled only by `end()` (never by `teardown()`, which runs on every drop). Internal so the NetworkRecovery extension can manage it.
    var networkTask: Task<Void, Never>?

    /// In-progress turn buffer. Stream emissions from the same speaker accumulate here; flush as one `transcripts` row on speaker switch or session end. Per CLAUDE.md, a transcripts row = one TURN, not one realtime-stream fragment.
    private struct TurnBuffer {
        let speaker: TranscriptChunk.Speaker
        var text: String
        let startedAt: Date
    }

    private var pendingTurn: TurnBuffer?

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
        startNetworkMonitoringIfNeeded()
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
                        "audio pump → NO MATCH provider=\(response.provider, privacy: .public) streamerIsPCM16=\(streamer is PCM16AudioStreamerType, privacy: .public) realtimeIsPersonaPlex=\(realtime is PersonaPlexSessionType, privacy: .public)",
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
                tConnectEnd: tConnectEnd,
            )

            // Free-cap mid-session enforcement. Fire-and-forget — a failed entitlement fetch leaves the session uncapped (premium-style) so a network blip doesn't end someone's conversation. Only schedules timers if the user is on free and a finite remaining window applies.
            scheduleFreeCapWrapUp(realtime: realtime)
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
            _ = try? await backend.endConversation(sessionId: id)
        }
        await teardown()
        // Audio upload AFTER teardown so the wav file is closed/finalized. Best-effort: a failed upload doesn't reopen the session — we just lose retention for that session. File is deleted whether upload succeeded or not so we don't accumulate local copies.
        if let id, let streamer {
            await uploadMicAudioIfAny(sessionId: id, streamer: streamer)
        }
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
        let toolStream = await client.toolCalls
        let toolTask = Task { [weak self] in
            for await call in toolStream {
                // Runs in its own task, off the audio path — the model keeps talking while recall resolves (async, like a human remembering mid-sentence), then the result is fed back.
                await self?.handleToolCall(call, client: client)
            }
        }
        observerTasks = [transcriptTask, errorTask, toolTask]
    }

    /// Fetch the entitlement, compute the smaller of the two remaining windows (day vs week), then schedule a wrap-up hint at `remaining - 30s` and a hard end at `remaining`. Premium users get no timers. Failures (network, decode) fail-open (no caps) — a single API blip should never end a paying user's conversation.
    private func scheduleFreeCapWrapUp(realtime: RealtimeClient) {
        Task { [weak self] in
            guard let self else { return }
            guard let entitlement = try? await backend.getEntitlement() else { return }
            if entitlement.isPremium { return }
            let remainingSec = min(
                entitlement.freeMinutesRemainingToday,
                entitlement.freeMinutesRemainingThisWeek,
            ) * 60
            guard remainingSec > 0 else {
                await end()
                return
            }
            let warnAt = max(remainingSec - 30, 5)
            let hintTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(warnAt) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await realtime.injectSystemHint(
                    "You have about 30 seconds left in this conversation before the user's free-plan limit ends the call. Wrap up naturally and warmly — a quick goodbye that fits your character. Don't ask new questions.",
                )
                await self?.logFreeCapEvent(stage: "warn", secondsRemaining: 30)
            }
            let endTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(remainingSec) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.logFreeCapEvent(stage: "hard_end", secondsRemaining: 0)
                await self?.end()
            }
            await self.storeFreeCapTasks([hintTask, endTask])
        }
    }

    private func storeFreeCapTasks(_ tasks: [Task<Void, Never>]) {
        freeCapTasks = tasks
    }

    private func logFreeCapEvent(stage: String, secondsRemaining: Int) {
        logger.error("free-cap \(stage, privacy: .public) — \(secondsRemaining, privacy: .public)s remaining")
    }

    private func appendTranscript(_ chunk: TranscriptChunk) {
        transcript.append(chunk)
        markAISpeaking(for: chunk)
        // Aggregate stream fragments into turn rows. Speaker switch (or session end) flushes the in-flight buffer as one POST → one DB row. Fragments from the same speaker join into one turn's text.
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
                endedAt: endedAt,
            )
        }
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
        sessionStartedAt = nil
        pendingTurn = nil
    }
}
