@testable import PalkieTalkie
import XCTest

/// Records the tool outputs SessionController submits back to the model.
private final class RecordingRealtimeClient: RealtimeClient, @unchecked Sendable {
    nonisolated(unsafe) var submitted: [(callId: String, output: String)] = []
    func open(wsUrl _: String, ephemeralToken _: String?) async throws {}
    func close() async {}
    func send(audio _: Data) async throws {}
    func waitForServerReady() async {}
    var inboundAudio: AsyncStream<Data> {
        get async { AsyncStream { $0.finish() } }
    }

    var transcript: AsyncStream<TranscriptChunk> {
        get async { AsyncStream { $0.finish() } }
    }

    var errors: AsyncStream<String> {
        get async { AsyncStream { $0.finish() } }
    }

    var bargeIn: AsyncStream<Void> {
        get async { AsyncStream { $0.finish() } }
    }

    func injectSystemHint(_: String) async {}
    func submitToolOutput(callId: String, output: String) async {
        submitted.append((callId, output))
    }
}

@MainActor
final class SessionControllerRecallToolTests: XCTestCase {
    /// The fake the controller-under-test posts to. Captured by makeController() so tests can assert on tool-call + session-end telemetry.
    private var backend: FakeConversationBackend!

    private func makeController() -> SessionController {
        let backend = FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "s",
                textPrompt: "",
                voiceId: "",
                wsUrl: "wss://t",
                provider: "openai",
                ephemeralToken: "ek",
                freeSecondsRemaining: nil,
                freeLimitKind: nil,
            ),
            endResponse: EndResponse(sessionId: "s", durationSeconds: 0),
        )
        self.backend = backend
        return SessionController(
            context: FakeContextGatherer(context: ConversationContext(
                localISOTime: "2025-01-01T00:00:00Z",
                timezone: "UTC",
                lat: 0,
                lon: 0,
                city: nil,
                weatherDescription: nil,
                temperatureC: nil,
                calendarEvents: [],
            )),
            backend: backend,
            micPermission: StubMicPermission(shouldThrow: false),
            streamerFactory: StubAudioStreamerFactory(streamer: FakeAudioStreamer()),
            sessionFactory: StubSessionFactory(session: FakePersonaPlexSession()),
            serverReadyTimeoutOverride: nil,
            pathMonitor: FakeNetworkPathMonitor(),
        )
    }

    func testWebFetchToolRoutesToBackendAndSubmitsResult() async {
        let controller = makeController()
        let client = RecordingRealtimeClient()
        await controller.handleToolCall(
            ToolCall(callId: "c1", name: "web_fetch", query: "https://news/x"), client: client,
        )
        XCTAssertEqual(client.submitted.count, 1)
        XCTAssertEqual(client.submitted.first?.callId, "c1")
        XCTAssertEqual(client.submitted.first?.output, "PAGE TEXT")
    }

    func testRecallFactsToolRoutesToBackend() async {
        let controller = makeController()
        let client = RecordingRealtimeClient()
        await controller.handleToolCall(
            ToolCall(callId: "c2", name: "recall_facts", query: "wes"), client: client,
        )
        XCTAssertEqual(client.submitted.first?.output, "FACTS")
    }

    func testEndConversationToolSetsFlagAndSubmitsNothing() async {
        let controller = makeController()
        let client = RecordingRealtimeClient()
        await controller.handleToolCall(
            ToolCall(callId: "c3", name: "end_conversation", query: ""), client: client,
        )
        XCTAssertTrue(client.submitted.isEmpty, "tearing down submits no tool output")
        // Nothing is playing here, so the navigator flag lands within a tick (no goodbye to wait out).
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(controller.endRequestedByTool)
    }

    func testUnknownToolSubmitsUnknownNote() async {
        let controller = makeController()
        let client = RecordingRealtimeClient()
        await controller.handleToolCall(
            ToolCall(callId: "c4", name: "made_up_tool", query: ""), client: client,
        )
        XCTAssertEqual(client.submitted.first?.output, "Unknown tool.")
    }

    func testEveryToolCallIsEchoedToBackend() async {
        let controller = makeController()
        let client = RecordingRealtimeClient()
        await controller.handleToolCall(
            ToolCall(callId: "c5", name: "recall_facts", query: "wes"), client: client,
        )
        await controller.handleToolCall(
            ToolCall(callId: "c6", name: "end_conversation", query: ""), client: client,
        )
        // The realtime WS is iOS↔provider direct, so the backend never sees a tool call unless iOS echoes it — including end_conversation, the only signal the model hung up.
        XCTAssertEqual(backend.toolCallCalls.map(\.name), ["recall_facts", "end_conversation"])
        XCTAssertEqual(backend.toolCallCalls.first?.query, "wes")
        XCTAssertNil(backend.toolCallCalls.last?.query, "end_conversation has no query, so none is reported")
    }

    func testNormalEndReportsUserLeft() async {
        let controller = makeController()
        controller.serverSessionId = "s"
        await controller.end()
        XCTAssertEqual(backend.sessionEndCalls.last?.reason, "user_left")
    }

    func testFreeCapEndReportsFreeCap() async {
        let controller = makeController()
        controller.serverSessionId = "s"
        controller.endedOnFreeCapLimit = true
        await controller.end()
        XCTAssertEqual(backend.sessionEndCalls.last?.reason, "free_cap")
    }

    func testEndConversationWaitsForTheGoodbyeAudioBeforeLeavingTalk() async {
        // Repro: the model says a goodbye line (still playing) then calls end_conversation; flagging the navigator immediately tears the session down and cuts the spoken goodbye off mid-audio. We must wait until the AI finishes speaking.
        let controller = makeController()
        let client = RecordingRealtimeClient()
        controller.isAISpeaking = true // goodbye still playing
        await controller.handleToolCall(
            ToolCall(callId: "c8", name: "end_conversation", query: ""), client: client,
        )
        XCTAssertFalse(
            controller.endRequestedByTool,
            "must not leave Talk while the goodbye is still playing",
        )
        controller.isAISpeaking = false // goodbye finished
        try? await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertTrue(controller.endRequestedByTool, "after the goodbye finishes, leave the Talk tab")
    }

    func testEndConversationWaitsForAudioDrainEvenAfterTheTranscriptStops() async {
        // The transcript runs ahead of the audio, so isAISpeaking can be false while the goodbye is still playing out. Gate on the actual audio drain, not the transcript, or the goodbye is never heard.
        let controller = makeController()
        let streamer = FakeAudioStreamer()
        streamer.outputPlaying = true // goodbye audio still draining
        controller.audioStreamer = streamer
        controller.isAISpeaking = false // transcript already finished (it's faster than audio)
        let client = RecordingRealtimeClient()
        await controller.handleToolCall(
            ToolCall(callId: "c9", name: "end_conversation", query: ""), client: client,
        )
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(controller.endRequestedByTool, "audio still draining → don't leave yet")
        streamer.outputPlaying = false // audio finished playing out
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(controller.endRequestedByTool, "audio drained → leave Talk")
    }

    func testToolEndReportsToolEvenAfterTheNavigatorClearsTheFlag() async {
        // Repro: MainTabView resets `endRequestedByTool` to false the instant it acts, BEFORE the resulting tab switch makes ConversationView disappear and run end(). An end-reason read from that flag would mislabel a model hang-up as `user_left`. The reason must come from a durable signal set when the tool fired.
        let controller = makeController()
        controller.serverSessionId = "s"
        let client = RecordingRealtimeClient()
        await controller.handleToolCall(
            ToolCall(callId: "c7", name: "end_conversation", query: ""), client: client,
        )
        controller.endRequestedByTool = false // the navigator already consumed and cleared it
        await controller.end()
        XCTAssertEqual(backend.sessionEndCalls.last?.reason, "tool")
    }
}
