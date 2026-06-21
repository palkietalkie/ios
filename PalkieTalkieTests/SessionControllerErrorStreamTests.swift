import Foundation
@testable import PalkieTalkie
import XCTest

/// Hits `startObserversForRealtime`'s error-stream branch: when the realtime client surfaces a server-side error, the controller flips phase from .live → .error.
@MainActor
final class SessionControllerErrorStreamTests: XCTestCase {
    func testServerErrorTransitionsPhaseToError() async {
        let session = FakePersonaPlexSession()
        let rig = makeController(session: session)
        await rig.controller.start()
        XCTAssertEqual(rig.controller.phase, SessionController.Phase.live)

        // Emit a server error via the fake session. The controller's error-stream observer should flip the phase.
        await session.emit(error: "modal container crashed")

        // The observer is detached on a Task; give it a tick to land.
        try? await Task.sleep(nanoseconds: 100_000_000)

        guard case let .error(message) = rig.controller.phase else {
            XCTFail("expected error phase, got \(rig.controller.phase)")
            return
        }
        XCTAssertEqual(message, "modal container crashed")

        // The failure must also be reported to the backend /events — without this, a remote tester's session failure leaves no server-side trace (the audio WS is iOS↔provider direct).
        let reported = rig.backend.sessionErrorCalls
        XCTAssertEqual(reported.count, 1)
        XCTAssertEqual(reported.first?.0, "s")
        XCTAssertEqual(reported.first?.1, "personaplex")
        XCTAssertEqual(reported.first?.2, "modal container crashed")
    }

    private struct Rig {
        let controller: SessionController
        let backend: FakeConversationBackend
    }

    private func makeController(session: FakePersonaPlexSession) -> Rig {
        let backend = FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "s", textPrompt: "", voiceId: "", wsUrl: "wss://test",
                provider: "personaplex", ephemeralToken: nil,
            ),
            endResponse: EndResponse(sessionId: "s", durationSeconds: 0),
        )
        let controller = SessionController(
            context: FakeContextGatherer(context: ConversationContext(
                localISOTime: "2026-01-01T00:00:00Z",
                timezone: "UTC", lat: nil, lon: nil,
                city: nil, weatherDescription: nil, temperatureC: nil,
                calendarEvents: [],
            )),
            backend: backend,
            micPermission: StubMicPermission(shouldThrow: false),
            streamerFactory: StubAudioStreamerFactory(streamer: FakeAudioStreamer()),
            sessionFactory: StubSessionFactory(session: session),
        )
        return Rig(controller: controller, backend: backend)
    }
}
