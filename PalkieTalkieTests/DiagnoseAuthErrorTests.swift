import ClerkKit
import Foundation
@testable import PalkieTalkie
import XCTest

/// `diagnoseAuthError` is the only thing standing between "a user in Osaka can't sign in" and us being able to debug it from the backend. These tests lock the two facts that make it useful: it surfaces the BURIED underlying-error code (which is the whole point — `ASAuthorizationError 1000`'s real cause is one layer down), and it preserves Clerk's structured rejection reason.
final class DiagnoseAuthErrorTests: XCTestCase {
    func testSurfacesUnderlyingErrorBeneathOpaqueTopLevel() {
        // Mirrors the real failure: ASAuthorizationError 1000 (.unknown) — opaque on its own — wrapping the AuthKit error that names the cause.
        let underlying = NSError(
            domain: "AKAuthenticationError", code: -7026,
            userInfo: [NSLocalizedDescriptionKey: "iCloud account not available"],
        )
        let top = NSError(
            domain: "com.apple.AuthenticationServices.AuthorizationError", code: 1000,
            userInfo: [
                NSLocalizedDescriptionKey: "The operation couldn’t be completed.",
                NSUnderlyingErrorKey: underlying,
            ],
        )
        let result = diagnoseAuthError(top)
        // The opaque top stays for context, but the real cause must be present — that's what localizedDescription threw away.
        XCTAssertTrue(result.contains("AuthorizationError#1000"))
        XCTAssertTrue(result.contains("AKAuthenticationError#-7026"))
        XCTAssertTrue(result.contains("iCloud account not available"))
    }

    func testPreservesClerkStructuredReason() throws {
        // ClerkAPIError's memberwise init is module-internal; its Codable init is the public path, so build one the way the SDK does — by decoding.
        let json = Data("""
        {"code":"oauth_token_invalid","message":"Invalid token","longMessage":"The Apple identity token audience does not match this instance.","clerkTraceId":"trace_abc123"}
        """.utf8)
        let clerk = try JSONDecoder().decode(ClerkAPIError.self, from: json)
        let result = diagnoseAuthError(clerk)
        XCTAssertTrue(result.contains("Clerk[oauth_token_invalid]"))
        XCTAssertTrue(result.contains("audience does not match"))
        XCTAssertTrue(result.contains("trace=trace_abc123"))
    }

    func testUnwrapsOurOAuthSessionFailure() {
        let inner = NSError(domain: "NSURLErrorDomain", code: -1009, userInfo: [NSLocalizedDescriptionKey: "offline"])
        let result = diagnoseAuthError(OAuthError.sessionFailed(inner))
        XCTAssertTrue(result.contains("OAuthError.sessionFailed"))
        XCTAssertTrue(result.contains("NSURLErrorDomain#-1009"))
    }

    func testCapsRunawayChainLength() {
        // A long localizedDescription must not let the reason exceed the backend field limit and get the whole report rejected.
        let huge = NSError(
            domain: "X",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: String(repeating: "z", count: 5000)],
        )
        XCTAssertLessThanOrEqual(diagnoseAuthError(huge).count, 1801)
    }
}
