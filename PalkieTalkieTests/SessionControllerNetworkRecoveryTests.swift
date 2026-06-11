@testable import PalkieTalkie
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
}
