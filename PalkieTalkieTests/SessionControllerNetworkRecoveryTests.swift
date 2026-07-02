@testable import PalkieTalkie
import UIKit
import XCTest

/// Mid-conversation network-drop recovery (the "elevator" bug): a live session that loses connectivity must tear down to `.reconnecting` instead of freezing on a green mic, and must auto-restart when the path returns. The fake path monitor drives the transitions; the fake session's open/close counts prove the dead session was torn down and a fresh one started.
@MainActor
final class SessionControllerNetworkRecoveryTests: XCTestCase {
    /// The monitor processes path changes on its own Task, so transitions land asynchronously — poll a MainActor condition until it holds or the deadline passes.
    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testMidCallDropTearsDownToReconnecting() async {
        let rig = makeSessionControllerRig()
        await rig.controller.start()
        XCTAssertEqual(rig.controller.phase, .live)

        rig.pathMonitor.goOffline()
        await waitUntil { rig.controller.phase == .reconnecting }

        XCTAssertEqual(rig.controller.phase, .reconnecting)
        let closeCount = await rig.session.closeCount
        XCTAssertEqual(closeCount, 1, "a drop must tear the dead session down, not leave a frozen .live mic")
    }

    func testAutoReconnectsWhenNetworkReturns() async {
        let rig = makeSessionControllerRig()
        await rig.controller.start()

        rig.pathMonitor.goOffline()
        await waitUntil { rig.controller.phase == .reconnecting }

        rig.pathMonitor.goOnline()
        await waitUntil { rig.controller.phase == .live }

        XCTAssertEqual(rig.controller.phase, .live)
        let openCount = await rig.session.openCount
        XCTAssertEqual(openCount, 2, "the path returning must start a fresh session, not stay dead")
    }

    /// The real failure the path-only monitor missed (verified from a device log: NSPOSIXErrorDomain 57 "Socket is not connected", network otherwise fine): the WS dies while NWPathMonitor stays ONLINE the whole time — a wifi→cellular handoff. The transport-disconnect signal, not a path-offline event, must drive the reconnect, AND the drop must be reported to the backend so user-device failures leave a server-side trace. The path monitor never fires here.
    func testTransportDeathWhilePathStaysOnlineReconnectsAndReports() async {
        let rig = makeSessionControllerRig()
        await rig.controller.start()
        XCTAssertEqual(rig.controller.phase, .live)

        // Socket dies; the path monitor is NOT touched (it stays "online").
        await rig.session.dropConnection()

        // phase is .live both before AND after the reconnect, so polling phase is useless — wait on the session actually being reopened.
        var opened = await rig.session.openCount
        let deadline = Date().addingTimeInterval(2)
        while opened < 2, Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
            opened = await rig.session.openCount
        }

        XCTAssertEqual(opened, 2, "the dead transport must be torn down and a fresh session opened")
        XCTAssertEqual(rig.controller.phase, .live, "after reconnect the session is live again")
        XCTAssertEqual(
            rig.backend.sessionErrorCalls.count,
            1,
            "the drop must be reported to the backend (the only server-side trace for a user device)",
        )
    }

    /// #2: a session that gets a server row at /start but then never becomes ready (serverReadyTimeout) must still be ended on the backend, otherwise its row is orphaned with a NULL ended_at forever (the no-ended_at rows seen in prod).
    func testFailedStartFlushesEndedAtSoTheRowIsntOrphaned() async {
        let rig = makeSessionControllerRig(serverReadyTimeout: 0.05)
        await rig.session.setHangServerReady(true) // WS opens but never signals ready → timeout
        await rig.controller.start()

        guard case .error = rig.controller.phase else {
            XCTFail("expected .error after the ready timeout, got \(rig.controller.phase)")
            return
        }
        let ended = await rig.backend.endCount
        XCTAssertEqual(ended, 1, "a failed-start session must be ended so ended_at is stamped, not left NULL")
    }

    /// #4: the spoken "Connection lost. Reconnecting." cue exists for when the user can't SEE the orange Reconnecting state (screen off / phone in a pocket on a walk). In the foreground the visible UI already covers it, so the gate must stay silent there to avoid nagging on every transient socket blip.
    func testReconnectCueSpeaksOnlyWhenAppNotForeground() {
        XCTAssertFalse(SessionController.shouldAnnounceReconnect(appState: .active))
        XCTAssertTrue(SessionController.shouldAnnounceReconnect(appState: .background))
        XCTAssertTrue(SessionController.shouldAnnounceReconnect(appState: .inactive))
    }
}
