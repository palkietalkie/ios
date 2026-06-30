@testable import PalkieTalkie
import XCTest

// MARK: - Fakes

struct FakeContextGatherer: ContextGathering {
    let context: ConversationContext
    func gather() async -> ConversationContext {
        context
    }
}

actor FakeConversationBackend: ConversationBackend {
    var startResponse: StartResponse
    var startError: Error?
    var endResponse: EndResponse
    var personas: [PersonaDTO]
    var entitlementResult: Result<Entitlement, Error> = .success(Entitlement(
        isPremium: true,
        freeMinutesRemainingToday: 10,
        freeMinutesRemainingThisWeek: 30,
        freeMinutesPerDayCap: 10,
        freeMinutesPerWeekCap: 30,
        premiumEndsAt: nil,
    ))
    var startCount = 0
    var endCount = 0
    var transcriptCalls: [(sessionId: String, speaker: String, text: String)] = []

    func setEntitlement(_ result: Result<Entitlement, Error>) {
        entitlementResult = result
    }

    init(
        startResponse: StartResponse,
        endResponse: EndResponse,
        startError: Error? = nil,
        personas: [PersonaDTO] = [
            PersonaDTO(
                id: UUID().uuidString,
                name: "Test",
                description: "",
                voiceId: "NATM1",
                role: nil,
                age: nil,
                background: nil,
                vocabularyRegister: nil,
                conversationalStyle: nil,
                topicalPreferences: nil,
                isPreset: true,
                isPublic: true,
                isOwner: false,
                likeCount: 0,
                likedByMe: false,
                sortWeight: nil,
            ),
        ],
    ) {
        self.startResponse = startResponse
        self.endResponse = endResponse
        self.startError = startError
        self.personas = personas
    }

    var startErrorOnce: Error?
    var startPersonaIds: [String] = []

    func setStartErrorOnce(_ error: Error) {
        startErrorOnce = error
    }

    func startConversation(
        personaId: String,
        context _: ConversationContext,
        topicOverride _: String?,
    ) async throws -> StartResponse {
        startCount += 1
        startPersonaIds.append(personaId)
        if let startError { throw startError }
        if let once = startErrorOnce {
            startErrorOnce = nil
            throw once
        }
        return startResponse
    }

    func endConversation(
        sessionId _: String, inputTokens _: Int?, outputTokens _: Int?,
    ) async throws -> EndResponse {
        endCount += 1
        return endResponse
    }

    func appendTranscript(
        sessionId: String,
        speaker: String,
        text: String,
        startedAt _: Date,
        endedAt _: Date,
    ) async throws {
        transcriptCalls.append((sessionId, speaker, text))
    }

    func recordColdStart(
        durationMs _: Int,
        phaseTimings _: ColdStartTimings,
        sessionId _: String,
    ) async throws {}

    nonisolated(unsafe) var pitchRangeCalls: [(String, Float, Float)] = []
    nonisolated(unsafe) var aiEmotionCalls: [(
        session: String,
        laugh: Int,
        cheer: Int,
        gasp: Int,
        sigh: Int,
        groan: Int,
    )] = []
    nonisolated(unsafe) var micUploads: [(String, Int)] = []
    nonisolated(unsafe) var sessionErrorCalls: [(String?, String, String)] = []
    nonisolated(unsafe) var modelUploads: [(String, Int)] = []
    nonisolated(unsafe) var pitchRangeError: Error?
    nonisolated(unsafe) var micUploadError: Error?
    nonisolated(unsafe) var modelUploadError: Error?

    func recordPitchRange(sessionId: String, minHz: Float, maxHz: Float) async throws {
        pitchRangeCalls.append((sessionId, minHz, maxHz))
        if let err = pitchRangeError { throw err }
    }

    func recordAIEmotions(
        sessionId: String, laugh: Int, cheer: Int, gasp: Int, sigh: Int, groan: Int,
    ) async throws {
        aiEmotionCalls.append((sessionId, laugh, cheer, gasp, sigh, groan))
    }

    func recordSessionError(sessionId: String?, provider: String, reason: String) async throws {
        sessionErrorCalls.append((sessionId, provider, reason))
    }

    nonisolated(unsafe) var toolCallCalls: [(sessionId: String?, name: String, query: String?)] = []
    nonisolated(unsafe) var sessionEndCalls: [(sessionId: String, reason: String)] = []

    func recordToolCall(sessionId: String?, name: String, query: String?) async throws {
        toolCallCalls.append((sessionId, name, query))
    }

    func recordSessionEnd(sessionId: String, reason: String) async throws {
        sessionEndCalls.append((sessionId, reason))
    }

    func uploadMicAudio(sessionId: String, deflatedWav: Data) async throws {
        micUploads.append((sessionId, deflatedWav.count))
        if let err = micUploadError { throw err }
    }

    func uploadModelAudio(sessionId: String, deflatedWav: Data) async throws {
        modelUploads.append((sessionId, deflatedWav.count))
        if let err = modelUploadError { throw err }
    }

    func getPersonas(search _: String?, sort _: String) async throws -> [PersonaDTO] {
        personas
    }

    func getEntitlement() async throws -> Entitlement {
        try entitlementResult.get()
    }

    var recallCalls: [(name: String, query: String)] = []

    func recallFacts(query: String) async throws -> String {
        recallCalls.append(("recall_facts", query))
        return "FACTS"
    }

    func recallConversations(query: String) async throws -> String {
        recallCalls.append(("recall_past_conversations", query))
        return "CONVERSATIONS"
    }

    func searchTranscripts(query: String) async throws -> String {
        recallCalls.append(("search_transcripts", query))
        return "TRANSCRIPTS"
    }

    func webFetch(url: String) async throws -> String {
        recallCalls.append(("web_fetch", url))
        return "PAGE TEXT"
    }
}

struct StubMicPermission: MicrophonePermissionRequesting {
    let shouldThrow: Bool
    func requestMicrophonePermission() async throws {
        if shouldThrow {
            throw AudioSessionError.microphonePermissionDenied
        }
    }
}

/// Drives connectivity transitions on demand. A struct (no `@unchecked`): AsyncStream + its Continuation are Sendable and share storage across copies, so `goOffline()`/`goOnline()` from the test reach the controller's monitor task. Emits nothing until called, so it's inert for tests that don't exercise recovery.
struct FakeNetworkPathMonitor: NetworkPathMonitoring {
    let stream: AsyncStream<Bool>
    let continuation: AsyncStream<Bool>.Continuation
    init() {
        (stream, continuation) = AsyncStream<Bool>.makeStream()
    }

    func statuses() -> AsyncStream<Bool> {
        stream
    }

    func goOffline() {
        continuation.yield(false)
    }

    func goOnline() {
        continuation.yield(true)
    }
}

/// Fake AudioStreamer that doesn't touch AVAudioEngine. Conforms to both AudioStreamerType (PersonaPlex / Opus path) and PCM16AudioStreamerType (OpenAI path) so tests can drive either provider's audio pump branch.
final class FakeAudioStreamer: AudioStreamerType, PCM16AudioStreamerType, @unchecked Sendable {
    nonisolated(unsafe) var played: [Data] = []
    nonisolated(unsafe) var playedPCM16: [Data] = []
    nonisolated(unsafe) var interruptCount = 0
    nonisolated(unsafe) var outputPlaying = false
    private let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
    private let (pcm16Stream, pcm16Continuation) = AsyncStream.makeStream(of: Data.self)
    nonisolated let pitchTracker = PitchTracker()
    nonisolated(unsafe) var emotionCountsValue: [String: Int] = [:]
    /// URLs the test can set so end()'s upload paths run with a known wav on disk.
    nonisolated(unsafe) var sessionAudioURL: URL?
    nonisolated(unsafe) var modelAudioURL: URL?
    nonisolated(unsafe) var stopCount = 0

    var inputChunks: AsyncStream<Data> {
        get async { stream }
    }

    var pcm16InputChunks: AsyncStream<Data> {
        get async { pcm16Stream }
    }

    var recordedSessionAudioURL: URL? {
        get async { sessionAudioURL }
    }

    var recordedModelAudioURL: URL? {
        get async { modelAudioURL }
    }

    func emotionCounts() async -> [String: Int] {
        emotionCountsValue
    }

    func playOutput(_ opusPacket: Data) async {
        played.append(opusPacket)
    }

    func playPCM16(_ pcm16Bytes: Data) async {
        playedPCM16.append(pcm16Bytes)
    }

    func interruptPlayback() async {
        interruptCount += 1
    }

    func stop() async {
        stopCount += 1
    }

    func isOutputPlaying() async -> Bool {
        outputPlaying
    }

    deinit {
        continuation.finish()
        pcm16Continuation.finish()
    }
}

struct StubAudioStreamerFactory: AudioStreamerFactory {
    let streamer: FakeAudioStreamer
    func makeStreamer() async throws -> AudioStreamerType {
        streamer
    }
}

actor FakePersonaPlexSession: PersonaPlexSessionType {
    private let (audioStream, audioCont) = AsyncStream.makeStream(of: Data.self)
    private let (transcriptStream, transcriptCont) = AsyncStream.makeStream(of: TranscriptChunk.self)
    private let (errorStream, errorCont) = AsyncStream.makeStream(of: String.self)
    private let (toolStream, toolCont) = AsyncStream.makeStream(of: ToolCall.self)
    private let (disconnectedStream, disconnectedCont) = AsyncStream.makeStream(of: String.self)
    var submittedOutputs: [(callId: String, output: String)] = []

    var openCount = 0
    var closeCount = 0
    var lastWSURL: String?
    var openError: Error?
    /// When true, `waitForServerReady` parks forever (mimics a WS that upgraded but never got `\x00` / session.created) until close() drains it — used to test SessionController's ready-timeout guard.
    var hangServerReady = false
    private var readyContinuation: CheckedContinuation<Void, Never>?

    func setHangServerReady(_ value: Bool) {
        hangServerReady = value
    }

    func open(wsUrl: String) async throws {
        openCount += 1
        lastWSURL = wsUrl
        if let openError { throw openError }
    }

    func open(wsUrl: String, ephemeralToken _: String?) async throws {
        try await open(wsUrl: wsUrl)
    }

    func close() async {
        closeCount += 1
        audioCont.finish()
        transcriptCont.finish()
        errorCont.finish()
        toolCont.finish()
        // Mirror the real client: draining the parked ready-waiter on close so a hung handshake doesn't leak its continuation.
        readyContinuation?.resume()
        readyContinuation = nil
    }

    nonisolated var toolCalls: AsyncStream<ToolCall> {
        get async { toolStream }
    }

    func submitToolOutput(callId: String, output: String) async {
        submittedOutputs.append((callId, output))
    }

    func emit(toolCall: ToolCall) {
        toolCont.yield(toolCall)
    }

    func send(control _: PersonaPlexClient.ControlAction) async throws {}
    func send(audio _: Data) async throws {}

    /// Completes immediately unless `hangServerReady` is set, in which case it parks until close() — exercising SessionController's ready-timeout guard.
    func waitForServerReady() async {
        if !hangServerReady { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            readyContinuation = c
        }
    }

    nonisolated var inboundAudio: AsyncStream<Data> {
        get async { audioStream }
    }

    nonisolated var transcript: AsyncStream<TranscriptChunk> {
        get async { transcriptStream }
    }

    nonisolated var errors: AsyncStream<String> {
        get async { errorStream }
    }

    nonisolated var bargeIn: AsyncStream<Void> {
        get async { AsyncStream { $0.finish() } }
    }

    func injectSystemHint(_: String) async {}

    func emit(transcript chunk: TranscriptChunk) {
        transcriptCont.yield(chunk)
    }

    func emit(error: String) {
        errorCont.yield(error)
    }

    nonisolated var disconnected: AsyncStream<String> {
        get async { disconnectedStream }
    }

    /// Simulate the transport dying mid-call (recv loop caught a socket error), WITHOUT any NWPathMonitor offline event — the wifi→cellular handoff case. Yields the recoverable disconnect signal and finishes the inbound streams like the real recv loop does.
    func dropConnection(reason: String = "Socket is not connected") {
        disconnectedCont.yield(reason)
        audioCont.finish()
        transcriptCont.finish()
    }
}

struct StubSessionFactory: PersonaPlexSessionFactory {
    let session: FakePersonaPlexSession
    func makeSession() -> PersonaPlexSessionType {
        session
    }
}

// MARK: - Tests

@MainActor
struct SessionControllerRig {
    let controller: SessionController
    let backend: FakeConversationBackend
    let session: FakePersonaPlexSession
    let streamer: FakeAudioStreamer
    let pathMonitor: FakeNetworkPathMonitor
}

@MainActor
final class SessionControllerTests: XCTestCase {
    private func makeController(
        backend: FakeConversationBackend? = nil,
        session: FakePersonaPlexSession = FakePersonaPlexSession(),
        streamer: FakeAudioStreamer = FakeAudioStreamer(),
        micThrows: Bool = false,
        serverReadyTimeout: Double? = nil,
    ) -> SessionControllerRig {
        let backend = backend ?? FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "srv-1",
                textPrompt: "hi",
                voiceId: "v1",
                wsUrl: "wss://test",
                provider: "personaplex",
                ephemeralToken: nil,
                freeSecondsRemaining: nil,
                freeLimitKind: nil,
            ),
            endResponse: EndResponse(sessionId: "srv-1", durationSeconds: 10),
        )
        let pathMonitor = FakeNetworkPathMonitor()
        let controller = SessionController(
            context: FakeContextGatherer(context: makeContext()),
            backend: backend,
            micPermission: StubMicPermission(shouldThrow: micThrows),
            streamerFactory: StubAudioStreamerFactory(streamer: streamer),
            sessionFactory: StubSessionFactory(session: session),
            serverReadyTimeoutOverride: serverReadyTimeout,
            pathMonitor: pathMonitor,
        )
        return SessionControllerRig(
            controller: controller, backend: backend, session: session, streamer: streamer, pathMonitor: pathMonitor,
        )
    }

    private func makeContext() -> ConversationContext {
        ConversationContext(
            localISOTime: "2025-01-01T00:00:00Z",
            timezone: "UTC",
            lat: nil, lon: nil, city: nil, calendarEvents: [],
        )
    }

    func testInitialPhaseIsIdle() {
        let rig = makeController()
        XCTAssertEqual(rig.controller.phase, .idle)
    }

    func testHappyPathReachesLive() async {
        let rig = makeController()
        await rig.controller.start()
        XCTAssertEqual(rig.controller.phase, SessionController.Phase.live)
        let openCount = await rig.session.openCount
        XCTAssertEqual(openCount, 1)
        let url = await rig.session.lastWSURL
        XCTAssertEqual(url, "wss://test")
    }

    func testMicrophoneDeniedTransitionsToError() async {
        let rig = makeController(micThrows: true)
        await rig.controller.start()
        guard case .error = rig.controller.phase else {
            return XCTFail("expected error phase, got \(rig.controller.phase)")
        }
    }

    func testBackendErrorTransitionsToError() async {
        let backend = FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "x", textPrompt: "", voiceId: "", wsUrl: "",
                provider: "personaplex", ephemeralToken: nil,
                freeSecondsRemaining: nil,
                freeLimitKind: nil,
            ),
            endResponse: EndResponse(sessionId: "x", durationSeconds: 0),
            startError: BackendError.notAuthenticated(reason: "test"),
        )
        let rig = makeController(backend: backend)
        await rig.controller.start()
        guard case .error = rig.controller.phase else {
            return XCTFail("expected error phase")
        }
    }

    /// Regression: cached UUID in UserDefaults pointed at a user-created persona that no longer exists in the DB (deleted, or dev DB reset). Old behavior: /start 404 → controller surfaces as .error → mic view dead. New behavior: 404 → re-resolve from /personas → retry once with the first preset → reach .live.
    func testStaleCachedPersonaRecoversOn404() async {
        let stalePersonaId = UUID().uuidString
        let freshPresetId = UUID().uuidString
        let backend = FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "srv-1",
                textPrompt: "hi",
                voiceId: "v1",
                wsUrl: "wss://test",
                provider: "personaplex",
                ephemeralToken: nil,
                freeSecondsRemaining: nil,
                freeLimitKind: nil,
            ),
            endResponse: EndResponse(sessionId: "srv-1", durationSeconds: 0),
            personas: [
                PersonaDTO(
                    id: freshPresetId,
                    name: "Fresh preset", description: "",
                    voiceId: "NATM1",
                    role: nil, age: nil, background: nil,
                    vocabularyRegister: nil, conversationalStyle: nil, topicalPreferences: nil,
                    isPreset: true, isPublic: true, isOwner: false,
                    likeCount: 0, likedByMe: false,
                ),
            ],
        )
        await backend.setStartErrorOnce(BackendError.http(404, "persona not found"))
        let rig = makeController(backend: backend)
        rig.controller.selectedPersonaId = stalePersonaId

        await rig.controller.start()

        XCTAssertEqual(rig.controller.phase, SessionController.Phase.live)
        let calls = await backend.startPersonaIds
        XCTAssertEqual(calls, [stalePersonaId, freshPresetId])
        XCTAssertEqual(rig.controller.selectedPersonaId, freshPresetId)
    }

    /// Regression: each realtime-stream fragment used to be a separate transcripts POST → one row per emission. PersonaPlex emits sub-word fragments like "fl"+"uff" → two rows. New behavior: aggregate fragments from the same speaker into one TURN row; flush on speaker switch and on session end.
    func testTurnAggregationCoalescesFragmentsFlushesOnSpeakerSwitch() async {
        let rig = makeController()
        await rig.controller.start()

        let now = Date()
        // Emits go to FakePersonaPlexSession's actor stream; the controller's observer Task drains them on MainActor.
        // Yield between emits so each chunk reaches `appendTranscript(_:)` before the next one (and before end()).
        let chunks = [
            TranscriptChunk(speaker: .persona, text: "Hey ", timestamp: now),
            TranscriptChunk(speaker: .persona, text: "Wes,", timestamp: now.addingTimeInterval(0.1)),
            TranscriptChunk(speaker: .persona, text: " how are you?", timestamp: now.addingTimeInterval(0.2)),
            // Speaker switch → flushes the persona turn.
            TranscriptChunk(speaker: .user, text: "good thanks", timestamp: now.addingTimeInterval(1.0)),
        ]
        for chunk in chunks {
            await rig.session.emit(transcript: chunk)
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        // End session → flushes the user turn.
        await rig.controller.end()

        // Wait for the fire-and-forget POST tasks to drain.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let calls = await rig.backend.transcriptCalls

        XCTAssertEqual(calls.count, 2, "two turns, not five fragments. got \(calls.map(\.text))")
        XCTAssertEqual(calls[0].speaker, "persona")
        XCTAssertEqual(calls[0].text, "Hey Wes, how are you?")
        XCTAssertEqual(calls[1].speaker, "user")
        XCTAssertEqual(calls[1].text, "good thanks")
    }

    func testEndCallsBackendAndTransitionsToIdle() async {
        let backend = FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "srv-2",
                textPrompt: "",
                voiceId: "",
                wsUrl: "wss://test",
                provider: "personaplex",
                ephemeralToken: nil,
                freeSecondsRemaining: nil,
                freeLimitKind: nil,
            ),
            endResponse: EndResponse(sessionId: "srv-2", durationSeconds: 0),
        )
        let rig = makeController(backend: backend)
        await rig.controller.start()
        XCTAssertEqual(rig.controller.phase, SessionController.Phase.live)
        await rig.controller.end()
        XCTAssertEqual(rig.controller.phase, .idle)
        let endCount = await backend.endCount
        XCTAssertEqual(endCount, 1)
        let closeCount = await rig.session.closeCount
        XCTAssertEqual(closeCount, 1)
    }

    func testEndReportsTutorEmotionCounts() async {
        let backend = FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "srv-emo",
                textPrompt: "",
                voiceId: "",
                wsUrl: "wss://test",
                provider: "personaplex",
                ephemeralToken: nil,
                freeSecondsRemaining: nil,
                freeLimitKind: nil,
            ),
            endResponse: EndResponse(sessionId: "srv-emo", durationSeconds: 0),
        )
        let streamer = FakeAudioStreamer()
        streamer.emotionCountsValue = ["laugh": 2, "cheer": 1, "gasp": 0, "sigh": 1, "groan": 0]
        let rig = makeController(backend: backend, streamer: streamer)
        await rig.controller.start()
        await rig.controller.end()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(backend.aiEmotionCalls.count, 1)
        let call = backend.aiEmotionCalls[0]
        XCTAssertEqual(call.laugh, 2)
        XCTAssertEqual(call.cheer, 1)
        XCTAssertEqual(call.sigh, 1)
    }

    func testEndDoesNotReportWhenNoTutorEmotions() async {
        let backend = FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "srv-noemo",
                textPrompt: "",
                voiceId: "",
                wsUrl: "wss://test",
                provider: "personaplex",
                ephemeralToken: nil,
                freeSecondsRemaining: nil,
                freeLimitKind: nil,
            ),
            endResponse: EndResponse(sessionId: "srv-noemo", durationSeconds: 0),
        )
        let streamer = FakeAudioStreamer() // emotionCountsValue defaults to empty
        let rig = makeController(backend: backend, streamer: streamer)
        await rig.controller.start()
        await rig.controller.end()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(backend.aiEmotionCalls.isEmpty, "no reaction means no event posted")
    }
}
