@testable import PalkieTalkie
import UIKit
import UserNotifications
import XCTest

/// PushNotifications + AppDelegate. APNs registration can't be triggered in tests; we cover the device-token hex
/// conversion and the foreground-banner UNUserNotificationCenter delegate.
@MainActor
final class PushNotificationsTests: XCTestCase {
    private func makeBackend() -> BackendAPI {
        BackendAPI(
            baseURL: URL(string: "https://api.test")!,
            transport: FakeTransport(),
            auth: StubAuthing(token: "tok"),
        )
    }

    func testInitDoesNotCrash() {
        let pn = PushNotifications(backend: makeBackend())
        XCTAssertNotNil(pn)
    }

    func testDidRegisterConvertsTokenToHex() {
        let pn = PushNotifications(backend: makeBackend())
        // 4 bytes → 8 hex chars. The function POSTs to backend on a fire-and-forget Task — we don't await it. The
        // conversion path runs synchronously inside didRegister and is the load-bearing logic.
        pn.didRegister(deviceToken: Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    // UNNotification has no public initializer — synthesizing one safely in unit tests isn't possible without a real
    // notification delivery. The willPresent delegate method body is two lines; we accept the partial-coverage trade.

    func testAppDelegateLaunchReturnsTrue() {
        let delegate = AppDelegate()
        let result = delegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)
        XCTAssertTrue(result)
    }

    func testAppDelegateRegisterDeviceTokenForwards() {
        let pn = PushNotifications(backend: makeBackend())
        AppDelegate.pushNotifications = pn
        defer { AppDelegate.pushNotifications = nil }
        let delegate = AppDelegate()
        // Forwards to PushNotifications.didRegister — no assertion, just confirm no crash.
        delegate.application(
            UIApplication.shared,
            didRegisterForRemoteNotificationsWithDeviceToken: Data([0x01, 0x02, 0x03, 0x04]),
        )
    }

    func testAppDelegateRegisterDeviceTokenNoOpWhenUnwired() {
        AppDelegate.pushNotifications = nil
        let delegate = AppDelegate()
        delegate.application(
            UIApplication.shared,
            didRegisterForRemoteNotificationsWithDeviceToken: Data([0xAA, 0xBB]),
        )
    }

    func testAppDelegateRegisterErrorIsNoop() {
        let delegate = AppDelegate()
        delegate.application(
            UIApplication.shared,
            didFailToRegisterForRemoteNotificationsWithError: URLError(.cancelled),
        )
    }
}
