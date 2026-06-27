@testable import PalkieTalkie
import XCTest

/// Pairs the start()/end() serialization in SessionController.
///
/// Repro for the tab-switch bug: leaving the Talk tab fires `Task { await end() }` (fire-and-forget), and returning re-fires `start()`. Because `start()` is slow (it parks in `awaitServerReady`), `end()` runs interleaved with the still-in-flight `start()`; its teardown calls `close()`, which drains the parked ready-waiter, so `start()` un-parks and marches on to `.live`, rebuilding the audio path over a transport `end()` already closed. Slow switching works only because `end()` finishes first.
@MainActor
final class SessionControllerLifecycleRaceTests: XCTestCase {
    func testEndWhileStartInFlightSettlesIdleNotLiveOverAClosedTransport() async {
        let session = FakePersonaPlexSession()
        await session.setHangServerReady(true)
        // Large timeout so the timeout path can't be what resolves start(); the race must be end()'s close() draining the ready waiter.
        let rig = makeSessionControllerRig(session: session, serverReadyTimeout: 10)

        let startTask = Task { await rig.controller.start() }
        await waitUntilConnecting(rig.controller)

        // User leaves Talk while start() is still parked at server-ready.
        await rig.controller.end()
        _ = await startTask.value

        // The user left: the session must be OVER, not live on top of a transport end() already tore down.
        XCTAssertEqual(
            rig.controller.phase,
            .idle,
            "start() resumed after end() and clobbered phase back to .live over a closed transport",
        )
    }

    private func waitUntilConnecting(_ controller: SessionController) async {
        for _ in 0 ..< 400 {
            if case .connecting = controller.phase { return }
            try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
        }
        XCTFail("start() never reached .connecting")
    }
}
