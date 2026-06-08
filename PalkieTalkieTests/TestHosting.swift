import SwiftUI
import UIKit
import XCTest

/// Shared SwiftUI host helper for tests that need a real render pipeline (UIHostingController + a window that has actually become key + a layout pass). Centralized so the iOS 26 `init(frame:)` deprecation (which requires anchoring on a UIWindowScene) is fixed in one place instead of seven copies.
@MainActor
enum TestHosting {
    static func host(_ view: some View, settleMs: UInt64 = 400) async {
        // iOS 26: `UIWindow(frame:)` and the no-arg `UIWindow()` are both deprecated — a window without a scene can't anchor view-controller presentations. Require a real UIWindowScene from UIApplication; the test bundle always has one because XCTest brings up the host app's scene before invoking tests.
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first
        else {
            XCTFail("test bundle started before any UIWindowScene was attached — host app not configured")
            return
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: settleMs * 1_000_000)
        controller.view.layoutIfNeeded()
        window.isHidden = true
    }
}
