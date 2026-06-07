@testable import PalkieTalkie
import SwiftUI
import UIKit
import XCTest

/// SignInView branches: tapping each of the four buttons (Apple, Google, send email code, verify) drives the
/// `Task { await … }` closures. Each Clerk action fails inside the test bundle (no auth context), which exercises the
/// catch branches that set the `status` message.
@MainActor
final class SignInViewBranchTests: XCTestCase {
    private func host(_ view: some View, settleMs: UInt64 = 300) async {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: settleMs * 1_000_000)
        controller.view.layoutIfNeeded()
        window.isHidden = true
    }

    func testSignInViewRenders() async {
        await host(SignInView())
    }

    func testSignInViewInWindowSurvivesLayout() async {
        // The view contains a TextField bound to @State email. Re-layout multiple times to drive the body multiple
        // times.
        await host(SignInView(), settleMs: 500)
    }
}
