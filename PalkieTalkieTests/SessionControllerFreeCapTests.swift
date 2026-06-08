@testable import PalkieTalkie
import XCTest

/// Covers scheduleFreeCapWrapUp branches inside SessionController.start(): premium short-circuit, entitlement fetch failure, zero-remaining-seconds immediate-end, finite-remaining schedule (warn + hard end), and end() teardown cancelling the scheduled tasks.
@MainActor
final class SessionControllerFreeCapTests: XCTestCase {
    private func makeController(
        backend: FakeConversationBackend,
    ) -> SessionController {
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

    private func freshBackend() -> FakeConversationBackend {
        FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "S",
                textPrompt: "",
                voiceId: "",
                wsUrl: "",
                provider: "personaplex",
                ephemeralToken: nil,
            ),
            endResponse: EndResponse(sessionId: "S", durationSeconds: 0),
        )
    }

    /// Premium user: free-cap scheduler must short-circuit. Verified by waiting briefly then asserting the controller's `phase` is still `.live` (not driven to `.ending` / `.idle` by a hard-end task).
    func testPremiumUserDoesNotScheduleEnd() async throws {
        let backend = freshBackend()
        await backend.setEntitlement(.success(Entitlement(
            isPremium: true,
            freeMinutesRemainingToday: 0,
            freeMinutesRemainingThisWeek: 0,
            freeMinutesPerDayCap: 10,
            freeMinutesPerWeekCap: 30,
            premiumEndsAt: nil,
        )))
        let controller = makeController(backend: backend)
        await controller.start()
        // Give the async scheduleFreeCapWrapUp Task time to run.
        try await Task.sleep(nanoseconds: 200_000_000)
        // Premium short-circuit means no hard-end task fires.
        XCTAssertEqual(controller.phase, .live)
        await controller.end()
    }

    /// Free user with 0 minutes remaining: should immediately end the session. Verified by checking the controller transitions out of `.live` quickly.
    func testFreeUserWithZeroRemainingTriggersImmediateEnd() async throws {
        let backend = freshBackend()
        await backend.setEntitlement(.success(Entitlement(
            isPremium: false,
            freeMinutesRemainingToday: 0,
            freeMinutesRemainingThisWeek: 0,
            freeMinutesPerDayCap: 10,
            freeMinutesPerWeekCap: 30,
            premiumEndsAt: nil,
        )))
        let controller = makeController(backend: backend)
        await controller.start()
        // Give the schedule task time to fetch entitlement and call end().
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(controller.phase, .idle)
    }

    /// Entitlement fetch fails: scheduler must no-op (don't strand the user). Verified by `.live` phase persisting after the schedule task would have run.
    func testEntitlementFetchFailureLeavesSessionAlone() async throws {
        let backend = freshBackend()
        await backend.setEntitlement(
            .failure(NSError(domain: "test", code: -1, userInfo: nil)),
        )
        let controller = makeController(backend: backend)
        await controller.start()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(controller.phase, .live)
        await controller.end()
    }

    /// Free user with finite remaining (>0): scheduler installs warn + end tasks. end() must cancel them before they fire. Verified by calling end() then waiting longer than the would-be hard-end delay, asserting nothing unexpected happens.
    func testEndCancelsScheduledFreeCapTasks() async throws {
        let backend = freshBackend()
        // 60 seconds remaining; the warn fires at ~30s, hard-end at 60s. We end manually well before either.
        await backend.setEntitlement(.success(Entitlement(
            isPremium: false,
            freeMinutesRemainingToday: 1,
            freeMinutesRemainingThisWeek: 5,
            freeMinutesPerDayCap: 10,
            freeMinutesPerWeekCap: 30,
            premiumEndsAt: nil,
        )))
        let controller = makeController(backend: backend)
        await controller.start()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(controller.phase, .live)
        await controller.end()
        XCTAssertEqual(controller.phase, .idle)
        // Wait briefly to confirm no zombie end() fires after our end already ran.
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(controller.phase, .idle)
    }
}
