import Foundation
@testable import PalkieTalkie
import XCTest

/// Coverage for the OpenAI provider branch in SessionController.start(). The PersonaPlex path is already covered by SessionControllerTests; this file pins the alternate provider wiring (factory selection, ephemeral token forwarded, PCM16 pump used).
@MainActor
final class SessionControllerOpenAITests: XCTestCase {
    /// Fake RealtimeClient that conforms to the protocol but doesn't open a real WebSocket. Records what the controller hands it so the OpenAI branch can be asserted.
    final class FakeRealtimeClient: RealtimeClient, @unchecked Sendable {
        nonisolated(unsafe) var openCount = 0
        nonisolated(unsafe) var closeCount = 0
        nonisolated(unsafe) var lastWSURL: String?
        nonisolated(unsafe) var lastToken: String?

        private let (audioStream, audioCont) = AsyncStream.makeStream(of: Data.self)
        private let (transcriptStream, transcriptCont) = AsyncStream.makeStream(of: TranscriptChunk.self)
        private let (errorStream, _) = AsyncStream.makeStream(of: String.self)
        private let (bargeInStream, _) = AsyncStream.makeStream(of: Void.self)

        func open(wsUrl: String, ephemeralToken: String?) async throws {
            openCount += 1
            lastWSURL = wsUrl
            lastToken = ephemeralToken
        }

        func close() async {
            closeCount += 1
            audioCont.finish()
            transcriptCont.finish()
        }

        func send(audio _: Data) async throws {}

        func waitForServerReady() async {}

        var inboundAudio: AsyncStream<Data> {
            get async { audioStream }
        }

        var transcript: AsyncStream<TranscriptChunk> {
            get async { transcriptStream }
        }

        var errors: AsyncStream<String> {
            get async { errorStream }
        }

        var bargeIn: AsyncStream<Void> {
            get async { bargeInStream }
        }

        func injectSystemHint(_: String) async {}
    }

    struct StubOpenAIFactory: OpenAIRealtimeClientFactory {
        let client: FakeRealtimeClient
        func makeClient(instructions _: String?) -> RealtimeClient {
            client
        }
    }

    func testOpenAIProviderUsesEphemeralToken() async {
        let fakeClient = FakeRealtimeClient()
        let backend = FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "S-O", textPrompt: "say hello",
                voiceId: "marin", wsUrl: "wss://api.openai.com/v1/realtime",
                provider: "openai", ephemeralToken: "ek_test_token",
                freeSecondsRemaining: nil,
                freeLimitKind: nil,
            ),
            endResponse: EndResponse(sessionId: "S-O", durationSeconds: 0),
        )
        let controller = SessionController(
            context: FakeContextGatherer(context: ConversationContext(
                localISOTime: "2026-01-01T00:00:00Z", timezone: "UTC",
                lat: nil, lon: nil, city: nil, calendarEvents: [],
            )),
            backend: backend,
            micPermission: StubMicPermission(shouldThrow: false),
            streamerFactory: StubAudioStreamerFactory(streamer: FakeAudioStreamer()),
            sessionFactory: StubSessionFactory(session: FakePersonaPlexSession()),
            openAIFactory: StubOpenAIFactory(client: fakeClient),
        )

        await controller.start()

        XCTAssertEqual(controller.phase, SessionController.Phase.live)
        XCTAssertEqual(fakeClient.openCount, 1)
        XCTAssertEqual(fakeClient.lastWSURL, "wss://api.openai.com/v1/realtime")
        XCTAssertEqual(fakeClient.lastToken, "ek_test_token")
    }

    func testOpenAIPathCallsCloseOnEnd() async {
        let fakeClient = FakeRealtimeClient()
        let backend = FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "S-O", textPrompt: "",
                voiceId: "marin", wsUrl: "wss://test",
                provider: "openai", ephemeralToken: "ek",
                freeSecondsRemaining: nil,
                freeLimitKind: nil,
            ),
            endResponse: EndResponse(sessionId: "S-O", durationSeconds: 0),
        )
        let controller = SessionController(
            context: FakeContextGatherer(context: ConversationContext(
                localISOTime: "2026-01-01T00:00:00Z", timezone: "UTC",
                lat: nil, lon: nil, city: nil, calendarEvents: [],
            )),
            backend: backend,
            micPermission: StubMicPermission(shouldThrow: false),
            streamerFactory: StubAudioStreamerFactory(streamer: FakeAudioStreamer()),
            sessionFactory: StubSessionFactory(session: FakePersonaPlexSession()),
            openAIFactory: StubOpenAIFactory(client: fakeClient),
        )

        await controller.start()
        await controller.end()

        XCTAssertEqual(fakeClient.closeCount, 1, "ending the session closes the OpenAI client")
        XCTAssertEqual(controller.phase, .idle)
    }

    /// startContextOverride is consumed once and reset.
    func testStartContextOverrideConsumedOnce() async {
        let backend = FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "S", textPrompt: "", voiceId: "",
                wsUrl: "wss://test", provider: "personaplex", ephemeralToken: nil,
                freeSecondsRemaining: nil,
                freeLimitKind: nil,
            ),
            endResponse: EndResponse(sessionId: "S", durationSeconds: 0),
        )
        let controller = SessionController(
            context: FakeContextGatherer(context: ConversationContext(
                localISOTime: "", timezone: "UTC",
                lat: nil, lon: nil, city: nil, calendarEvents: [],
            )),
            backend: backend,
            micPermission: StubMicPermission(shouldThrow: false),
            streamerFactory: StubAudioStreamerFactory(streamer: FakeAudioStreamer()),
            sessionFactory: StubSessionFactory(session: FakePersonaPlexSession()),
        )
        controller.startContextOverride = "talk about hiking"
        await controller.start()
        XCTAssertNil(controller.startContextOverride, "override consumed after one use")
    }
}
