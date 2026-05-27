import Foundation
import UIKit
import UserNotifications

/// Handles APNs registration and forwards the device token to the backend so scheduled-session reminders can be
/// delivered.
final class PushNotifications: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = PushNotifications()

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
        Task {
            try? await BackendAPI.shared.registerPushToken(hex)
        }
    }

    /// Show banner even when app is foreground — reminders are time-sensitive.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotifications.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError _: Error) {}
}
