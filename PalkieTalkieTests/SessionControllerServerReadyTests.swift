@testable import PalkieTalkie
import XCTest

/// Pairs SessionController+ServerReady.swift.
@MainActor
final class SessionControllerServerReadyTests: XCTestCase {
    /// Regression: when the WS upgraded but the server never sent its ready signal (`\x00` / session.created), `waitForServerReady` parked forever and the UI showed "Loading your tutor…" indefinitely. The bounded wait must convert that hang into an error phase the user can retry from.
    func testServerReadyTimeoutSurfacesErrorInsteadOfHanging() async {
        let session = FakePersonaPlexSession()
        await session.setHangServerReady(true)
        let rig = makeSessionControllerRig(session: session, serverReadyTimeout: 0.05)
        await rig.controller.start()
        guard case .error = rig.controller.phase else {
            return XCTFail("expected error phase on ready-timeout, got \(rig.controller.phase)")
        }
        // The hung session must be torn down (close drains the parked waiter).
        let closeCount = await session.closeCount
        XCTAssertEqual(closeCount, 1)
    }
}
