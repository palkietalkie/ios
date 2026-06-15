import AuthenticationServices
@testable import PalkieTalkie
import XCTest

/// Locks which errors count as "user backed out" — these must be treated as no-ops, never as failures that alert the feed.
final class IsUserCancellationTests: XCTestCase {
    func testOAuthUserCancelled() {
        XCTAssertTrue(isUserCancellation(OAuthError.userCancelled))
    }

    func testWebAuthSheetDismissed() {
        // The exact error Google sign-in produced: WebAuthenticationSession error 1 (canceledLogin).
        let err = NSError(
            domain: ASWebAuthenticationSessionError.errorDomain,
            code: ASWebAuthenticationSessionError.Code.canceledLogin.rawValue,
        )
        XCTAssertTrue(isUserCancellation(err))
    }

    func testNativeAppleCancelled() {
        let err = NSError(domain: ASAuthorizationError.errorDomain, code: ASAuthorizationError.Code.canceled.rawValue)
        XCTAssertTrue(isUserCancellation(err))
    }

    func testRealFailureIsNotCancellation() {
        // ASAuthorizationError 1000 (the real error-1000 case) must STILL alert — it's not a cancel.
        let err = NSError(domain: ASAuthorizationError.errorDomain, code: ASAuthorizationError.Code.unknown.rawValue)
        XCTAssertFalse(isUserCancellation(err))
        XCTAssertFalse(isUserCancellation(NSError(domain: "SomeOther", code: 1)))
    }
}
