@testable import PalkieTalkie
import XCTest

/// scheduleFreeCapWrapUp is driven by the precise `StartResponse.freeSecondsRemaining`: nil (premium / unlimited) schedules nothing; a finite value installs warn + hard-end timers that an explicit end() cancels; a tiny value lets the hard-end fire, ending the session and flagging `endedOnFreeCapLimit` so the UI can explain what happened.
@MainActor
final class SessionControllerFreeCapTests: XCTestCase {
    private func makeController(backend: FakeConversationBackend) -> SessionController {
        SessionController(
            context: FakeContextGatherer(context: ConversationContext(
                localISOTime: "2026-01-01T00:00:00Z", timezone: "UTC",
                lat: nil, lon: nil, city: nil, weatherDescription: nil,
                temperatureC: nil, calendarEvents: [],
            )),
            backend: backend,
            micPermission: StubMicPermission(shouldThrow: false),
            streamerFactory: StubAudioStreamerFactory(streamer: FakeAudioStreamer()),
            sessionFactory: StubSessionFactory(session: FakePersonaPlexSession()),
        )
    }

    private func backend(
        freeSecondsRemaining: Int?, freeLimitKind: String? = nil,
    ) -> FakeConversationBackend {
        FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "S", textPrompt: "", voiceId: "", wsUrl: "",
                provider: "personaplex", ephemeralToken: nil,
                freeSecondsRemaining: freeSecondsRemaining,
                freeLimitKind: freeLimitKind,
            ),
            endResponse: EndResponse(sessionId: "S", durationSeconds: 0),
        )
    }

    /// nil remaining (premium / unlimited): no timers, the session just stays live.
    func testUnlimitedSchedulesNothing() async throws {
        let controller = makeController(backend: backend(freeSecondsRemaining: nil))
        await controller.start()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(controller.phase, .live)
        XCTAssertFalse(controller.endedOnFreeCapLimit)
        await controller.end()
    }

    /// Finite remaining installs the warn + hard-end timers; an explicit end() must cancel them so no zombie hard-end fires afterward, and a manual end is not a cap hit.
    func testEndCancelsScheduledTimers() async throws {
        let controller = makeController(backend: backend(freeSecondsRemaining: 60, freeLimitKind: "daily"))
        await controller.start()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(controller.phase, .live)
        await controller.end()
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertFalse(controller.endedOnFreeCapLimit, "a manual end is not a cap hit")
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(controller.phase, .idle)
    }

    /// A tiny remaining window: the hard-end timer fires, ends the session, flags the cap hit, and records WHICH limit so the UI can say "today" vs "this week".
    func testHardEndFiresAndFlagsCapLimitKind() async throws {
        let controller = makeController(backend: backend(freeSecondsRemaining: 1, freeLimitKind: "weekly"))
        await controller.start()
        XCTAssertEqual(controller.phase, .live)
        // The hard-end task sleeps 1s then ends; wait past it.
        try await Task.sleep(nanoseconds: 1_400_000_000)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertTrue(controller.endedOnFreeCapLimit)
        XCTAssertEqual(controller.freeCapLimitKind, "weekly")
        XCTAssertTrue(controller.reviewLastTranscript)
        // Dismissing the cover ("Not now") hides the overlay but keeps the transcript visible to review.
        controller.endedOnFreeCapLimit = false
        XCTAssertTrue(controller.reviewLastTranscript, "transcript stays available after dismiss")
    }
}
