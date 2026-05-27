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
    var startCount = 0
    var endCount = 0
    var transcriptCalls: [(sessionId: String, speaker: String, text: String)] = []

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
                likedByMe: false
            )
        ]
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
        topicOverride _: String?
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

    func endConversation(sessionId _: String) async throws -> EndResponse {
        endCount += 1
        return endResponse
    }

    func appendTranscript(
        sessionId: String,
        speaker: String,
        text: String,
        startedAt _: Date,
        endedAt _: Date
    ) async throws {
        transcriptCalls.append((sessionId, speaker, text))
    }

    func recordColdStart(
        durationMs _: Int,
        phaseTimings _: ColdStartTimings,
        sessionId _: String
    ) async throws {}

    func getPersonas(search _: String?, sort _: String) async throws -> [PersonaDTO] {
        personas
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

/// Fake AudioStreamer that doesn't touch AVAudioEngine.
final class FakeAudioStreamer: AudioStreamerType, @unchecked Sendable {
    nonisolated(unsafe) var played: [Data] = []
    private let (stream, continuation) = AsyncStream.makeStream(of: Data.self)

    var inputChunks: AsyncStream<Data> {
        get async { stream }
    }

    func playOutput(_ opusPacket: Data) async {
        played.append(opusPacket)
    }

    deinit {
        continuation.finish()
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

    var openCount = 0
    var closeCount = 0
    var lastWSURL: String?
    var openError: Error?

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
    }

    func send(control _: PersonaPlexClient.ControlAction) async throws {}
    func send(audio _: Data) async throws {}

    /// Test fakes complete handshake immediately so tests don't deadlock.
    func waitForServerReady() async {}

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

    func emit(transcript chunk: TranscriptChunk) {
        transcriptCont.yield(chunk)
    }

    func emit(error: String) {
        errorCont.yield(error)
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
}

@MainActor
final class SessionControllerTests: XCTestCase {
    private func makeController(
        backend: FakeConversationBackend? = nil,
        session: FakePersonaPlexSession = FakePersonaPlexSession(),
        streamer: FakeAudioStreamer = FakeAudioStreamer(),
        micThrows: Bool = false
    ) -> SessionControllerRig {
        let backend = backend ?? FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "srv-1",
                textPrompt: "hi",
                voiceId: "v1",
                wsUrl: "wss://test",
                provider: "personaplex",
                ephemeralToken: nil
            ),
            endResponse: EndResponse(sessionId: "srv-1", durationSeconds: 10)
        )
        let controller = SessionController(
            context: FakeContextGatherer(context: makeContext()),
            backend: backend,
            micPermission: StubMicPermission(shouldThrow: micThrows),
            streamerFactory: StubAudioStreamerFactory(streamer: streamer),
            sessionFactory: StubSessionFactory(session: session)
        )
        return SessionControllerRig(controller: controller, backend: backend, session: session, streamer: streamer)
    }

    private func makeContext() -> ConversationContext {
        ConversationContext(
            localISOTime: "2025-01-01T00:00:00Z",
            timezone: "UTC",
            lat: 0,
            lon: 0,
            city: nil,
            weatherDescription: nil,
            temperatureC: nil,
            calendarEvents: []
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
                provider: "personaplex", ephemeralToken: nil
            ),
            endResponse: EndResponse(sessionId: "x", durationSeconds: 0),
            startError: BackendError.notAuthenticated(reason: "test")
        )
        let rig = makeController(backend: backend)
        await rig.controller.start()
        guard case .error = rig.controller.phase else {
            return XCTFail("expected error phase")
        }
    }

    /// Regression: cached UUID in UserDefaults pointed at a user-created persona that no longer exists in the DB
    /// (deleted, or dev DB reset). Old behavior: /start 404 → controller surfaces as .error → mic view dead. New
    /// behavior: 404 → re-resolve from /personas → retry once with the first preset → reach .live.
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
                ephemeralToken: nil
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
                    likeCount: 0, likedByMe: false
                )
            ]
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

    /// Regression: each realtime-stream fragment used to be a separate transcripts POST → one row per emission.
    /// PersonaPlex emits sub-word fragments like "fl"+"uff" → two rows. New behavior: aggregate fragments from the same
    /// speaker into one TURN row; flush on speaker switch and on session end.
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
            TranscriptChunk(speaker: .user, text: "good thanks", timestamp: now.addingTimeInterval(1.0))
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
                ephemeralToken: nil
            ),
            endResponse: EndResponse(sessionId: "srv-2", durationSeconds: 0)
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
}
