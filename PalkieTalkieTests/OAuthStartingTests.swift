@testable import PalkieTalkie
import XCTest

/// Smoke test for the `OAuthStarting` protocol seam and its default wiring. The full catch-branch coverage lives in `IntegrationsViewModelTests` where a fake `OAuthStarting` drives each canned outcome.
@MainActor
final class OAuthStartingTests: XCTestCase {
    func testDefaultOAuthStarterConstructs() {
        let starter: any OAuthStarting = DefaultOAuthStarter()
        // Type-conformance is the contract being pinned. Calling start(authURL:) would launch the system browser, which would either crash without a UIWindowScene or block the test runner — see IntegrationsViewModelTests for fake-based coverage of the real call surface.
        _ = starter
    }
}
