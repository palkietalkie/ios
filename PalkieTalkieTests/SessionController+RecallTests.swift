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
    private func makeController() -> SessionController {
        SessionController(
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
            backend: FakeConversationBackend(
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
            ),
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
        XCTAssertTrue(controller.endRequestedByTool)
        XCTAssertTrue(client.submitted.isEmpty, "tearing down submits no tool output")
    }

    func testUnknownToolSubmitsUnknownNote() async {
        let controller = makeController()
        let client = RecordingRealtimeClient()
        await controller.handleToolCall(
            ToolCall(callId: "c4", name: "made_up_tool", query: ""), client: client,
        )
        XCTAssertEqual(client.submitted.first?.output, "Unknown tool.")
    }
}
