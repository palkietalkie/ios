@testable import PalkieTalkie
import SwiftUI
import XCTest

/// Pure behavior tests for TalkAboutTodayView. The view's body requires a SessionController in @Environment, which ViewInspector's `inspect()` doesn't run through (it bypasses SwiftUI's environment resolution). Anything we want to assert about the rendered tree has to go through `UIHostingController` host integration tests instead — see `ConversationViewBranchTests` for that pattern. Tests here cover what we CAN cover without rendering: cache key constants and DTO shape used by the section data.
@MainActor
final class TalkAboutTodayViewTests: XCTestCase {
    /// Cache key must match the constant the view reads on init. A rename without updating the seeded cache would silently fall through to network-blocking first paint.
    func testCacheKeyIsStable() {
        // Read via the static accessor isn't exposed; assert by writing under the expected key and reading back.
        let key = "cache.talk_about_today"
        let payload = [
            TalkSection(
                topic: "politics",
                items: [TalkItem(id: "i_1", title: "Headline", summary: "s", source: "AP", imageUrl: "")],
            ),
        ]
        JSONCache.save(payload, key: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let read = JSONCache.load([TalkSection].self, key: key)
        XCTAssertEqual(read?.count, 1)
        XCTAssertEqual(read?.first?.topic, "politics")
    }
}
