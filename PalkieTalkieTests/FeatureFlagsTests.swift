@testable import PalkieTalkie
import XCTest

final class FeatureFlagsTests: XCTestCase {
    /// Guards the App Review 2.1(b) contract: subscriptions MUST stay off until the Paid Applications Agreement is Active (tax + banking filed under the company EIN, Apple account converted to Organization). While it's pending StoreKit returns no products, so any purchasable-subscription reference is a guaranteed rejection. This test fails the moment someone flips the flag, forcing them to confirm the agreement is live first.
    func testSubscriptionsStayDisabledUntilPaidAgreementIsActive() {
        XCTAssertFalse(FeatureFlags.subscriptionsEnabled)
    }
}
