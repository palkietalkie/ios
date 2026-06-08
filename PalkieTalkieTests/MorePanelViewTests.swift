@testable import PalkieTalkie
import SwiftUI
import ViewInspector
import XCTest

/// Regression tests for `MorePanelView`. Two prior attempts at switching the nav links from direct-destination to value-based pattern broke every tap inside this tab — the destination would push then bounce back. These tests pin the contract: every advertised sub-screen MUST have a tappable NavigationLink with the correct label. If anyone tries to swap to a form that breaks the push (label-only row, broken `navigationDestination(for:)` wiring), the lookup throws and the test fails.
@MainActor
final class MorePanelViewTests: XCTestCase {
    /// Every expected sub-screen entry must be reachable as a `NavigationLink` whose label contains the expected text. We use `find(navigationLink:)` per label rather than `findAll` because findAll recurses into the destination subtrees (e.g. IntegrationsView's inner rows), polluting any structural count.
    func testMorePanelHasNavigationLinkForEachExpectedLabel() throws {
        let sut = MorePanelView()
        let expectedLabels = [
            "Profile",
            "Practice",
            "Integrations",
            "Privacy & Data",
            "Display language",
            "Past conversations",
            "Subscription",
        ]
        for label in expectedLabels {
            XCTAssertNoThrow(
                try sut.inspect().find(navigationLink: label),
                "expected a NavigationLink labeled '\(label)' in MorePanelView. If this fails, a sub-screen entry was removed, its label changed, or its NavigationLink wrapping was lost — which is the bug pattern that broke taps twice before.",
            )
        }
    }

    /// Sign out is a Button, not a NavigationLink. Lock it in separately so a future refactor can't quietly drop it.
    func testMorePanelHasSignOutButton() throws {
        let sut = MorePanelView()
        XCTAssertNoThrow(
            try sut.inspect().find(button: "Sign out"),
            "expected a Sign out Button in MorePanelView",
        )
    }
}
