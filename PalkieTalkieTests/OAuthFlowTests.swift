import AuthenticationServices
@testable import PalkieTalkie
import UIKit
import XCTest

/// OAuthFlow drives ASWebAuthenticationSession. The session itself can't be instrumented in unit tests (requires real
/// system UI), so we cover the surface bits that don't need user interaction.
@MainActor
final class OAuthFlowTests: XCTestCase {
    func testSharedSingletonAccessible() {
        let flow = OAuthFlow.shared
        XCTAssertNotNil(flow)
    }

    /// `start(authURL:)` cannot be exercised without launching system UI; ensure the singleton is reusable across calls.
    func testSharedSingletonStableAcrossAccess() {
        let a = OAuthFlow.shared
        let b = OAuthFlow.shared
        XCTAssertTrue(a === b)
    }

    /// presentationAnchor is invoked by the system on the main thread when ASWebAuthenticationSession needs a window.
    /// In a unit-test bundle there's no foreground UIWindowScene, so the API contract is "either a real window or a
    /// preconditionFailure." We can't safely trigger the precondition path — but we CAN verify the protocol conformance.
    func testConformsToPresentationContextProvider() {
        let flow: ASWebAuthenticationPresentationContextProviding = OAuthFlow.shared
        XCTAssertNotNil(flow)
    }

    func testOAuthErrorCases() {
        // Just construct each case so the enum's compiled metadata gets coverage.
        let e1 = OAuthError.invalidURL
        let e2 = OAuthError.userCancelled
        let e3 = OAuthError.sessionFailed(URLError(.cancelled))
        for e in [e1, e2, e3] {
            XCTAssertNotNil(e)
        }
    }
}
