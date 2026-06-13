@testable import PalkieTalkie
import XCTest

/// Locks the routing decision behind `RootView`, especially the case that caused the on-sign-in flip: a freshly-signed-in user whose gates haven't loaded must WAIT, not flash `MainTabView`.
final class ResolveRootDestinationTests: XCTestCase {
    func testSignedInWithUnknownGatesWaitsInsteadOfFlashingMain() {
        // The bug: gates nil → fell through to .main → then flipped to .onboarding once they loaded.
        let dest = resolveRootDestination(
            isLoading: false, userSignedIn: true, consentSet: nil, profileComplete: nil,
        )
        XCTAssertEqual(dest, .loading)
    }

    func testConsentUnknownButProfileKnownStillWaits() {
        // Either gate unknown must hold at .loading — partial state must not leak a wrong screen.
        let dest = resolveRootDestination(
            isLoading: false, userSignedIn: true, consentSet: nil, profileComplete: false,
        )
        XCTAssertEqual(dest, .loading)
    }

    func testNotSignedInGoesToSignIn() {
        XCTAssertEqual(
            resolveRootDestination(isLoading: false, userSignedIn: false, consentSet: nil, profileComplete: nil),
            .signIn,
        )
    }

    func testLoadingWinsOverEverything() {
        XCTAssertEqual(
            resolveRootDestination(isLoading: true, userSignedIn: true, consentSet: true, profileComplete: true),
            .loading,
        )
    }

    func testConsentGateBeforeOnboarding() {
        XCTAssertEqual(
            resolveRootDestination(isLoading: false, userSignedIn: true, consentSet: false, profileComplete: false),
            .consent,
        )
    }

    func testOnboardingWhenProfileIncomplete() {
        XCTAssertEqual(
            resolveRootDestination(isLoading: false, userSignedIn: true, consentSet: true, profileComplete: false),
            .onboarding,
        )
    }

    func testMainOnlyWhenBothGatesPassed() {
        XCTAssertEqual(
            resolveRootDestination(isLoading: false, userSignedIn: true, consentSet: true, profileComplete: true),
            .main,
        )
    }
}
