import ClerkKit
@testable import PalkieTalkie
import XCTest

/// The bug: a valid email code whose sign-in did NOT reach `.complete` created no session, yet the old code discarded the result and reported success — bouncing the user back to the sign-in screen. These pin that any non-complete terminal state is now a thrown error.
final class RequireSignInCompleteTests: XCTestCase {
    func testSignInCompletePasses() throws {
        try requireSignInComplete(status: .complete)
    }

    func testSignInNeedsSecondFactorThrows() {
        XCTAssertThrowsError(try requireSignInComplete(status: .needsSecondFactor)) { error in
            guard case SignInServiceError.verificationIncomplete = error else {
                return XCTFail("expected .verificationIncomplete, got \(error)")
            }
        }
    }
}
