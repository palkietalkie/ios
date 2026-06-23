import UIKit
import UserNotifications

/// The localized title + body for the free-cap notification, split daily vs weekly so it reads right (the weekly block lasts until Monday). Pure so the text selection is unit-testable; the OS call below is not.
func freeCapNotificationText(isWeekly: Bool) -> (title: String, body: String) {
    isWeekly
        ? (
            String(localized: "Nice work this week!"),
            String(
                localized: "You've made the most of this week's free practice. It refreshes Monday, or upgrade for unlimited anytime.",
            ),
        )
        : (
            String(localized: "Nice work today!"),
            String(
                localized: "You've made the most of today's free practice. It refreshes tomorrow, or upgrade for unlimited anytime.",
            ),
        )
}

/// Fire a local notification when the user hits their free-plan cap mid-session. The point is the backgrounded case: on a walk with the screen off (background-audio session), they'd never see the in-app limit card, so without this the session just goes silent. Best-effort, silently no-ops if notifications aren't authorized; the same identifier replaces any prior so caps don't stack up.
@MainActor
func notifyFreeCapReached(isWeekly: Bool) {
    // Foreground is already covered by the inline limit card + spoken line, and our UN delegate shows banners even in foreground — so posting here too would double-banner. Only reach out when not active.
    guard UIApplication.shared.applicationState != .active else { return }
    let text = freeCapNotificationText(isWeekly: isWeekly)
    let content = UNMutableNotificationContent()
    content.title = text.title
    content.body = text.body
    content.sound = .default
    UNUserNotificationCenter.current().add(
        UNNotificationRequest(identifier: "freecap-limit", content: content, trigger: nil),
    )
}
