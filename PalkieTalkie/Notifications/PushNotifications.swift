import Foundation
import UIKit
import UserNotifications

/// Handles APNs registration and forwards the device token to the backend so scheduled-session reminders can be delivered. Used to be `PushNotifications.shared` + `BackendAPI.shared`; now backend is constructor-injected so tests can hand in a fake.
final class PushNotifications: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let backend: BackendAPI

    init(backend: BackendAPI) {
        self.backend = backend
    }

    func bootstrap() async {
        UNUserNotificationCenter.current().delegate = self
        let granted = await (try? UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        guard granted else { return }
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        let backend = backend
        Task {
            try? await backend.registerPushToken(hex)
        }
    }

    /// Show banner even when app is foreground — reminders are time-sensitive.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void,
    ) {
        completionHandler([.banner, .sound])
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set by `PalkieTalkieApp.init` so the OS-driven `didRegisterForRemoteNotifications` callback can forward the device token. The UIApplicationDelegateAdaptor instantiates this class without arguments, so we can't pass the `PushNotifications` instance through init — it has to live on a static the app sets at launch.
    nonisolated(unsafe) static var pushNotifications: PushNotifications?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil,
    ) -> Bool {
        true
    }

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data,
    ) {
        Self.pushNotifications?.didRegister(deviceToken: deviceToken)
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError _: Error) {}
}
