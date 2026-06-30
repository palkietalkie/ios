@testable import PalkieTalkie
import SwiftUI
import XCTest

@MainActor
final class MainTabViewSwipeTests: XCTestCase {
    func testTopicsTabYieldsHorizontalSwipeToItsCarousel() {
        // Bug: swiping the Topics horizontal carousel also fired the cross-tab swipe and flipped to Persona. The Topics tab must disable the cross-tab gesture so its subview carousel keeps the drag.
        XCTAssertEqual(MainTabView.crossTabSwipeMask(for: .today), .subviews)
    }

    func testOtherTabsKeepCrossTabSwipe() {
        for tab in [MainTabView.AppTab.persona, .talk, .stats, .more] {
            XCTAssertEqual(MainTabView.crossTabSwipeMask(for: tab), .all)
        }
    }
}
