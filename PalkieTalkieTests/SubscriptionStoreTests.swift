@testable import PalkieTalkie
import XCTest

/// StoreKit 2 wrapper. Most behavior (loadProducts, purchase, restore) requires a sandbox StoreKit session that we can't spin up in unit tests — XCUI is the right harness for those. The pure-logic surfaces we CAN test deterministically: initial state, error pass-through, and that the type publishes the observable shape the UI binds to.
@MainActor
final class SubscriptionStoreTests: XCTestCase {
    /// A freshly-constructed store has no loaded products, no entitlement, and no error. SubscriptionView reads these on first appear to decide which row to render — an init that pre-populates any of them would break the empty-state UI.
    func testInitialStateIsEmpty() {
        let store = SubscriptionStore()
        XCTAssertTrue(store.products.isEmpty)
        XCTAssertNil(store.entitled)
        XCTAssertNil(store.error)
    }

    /// `error` is the one mutable knob the UI binds via TwoWay binding (clears the alert when dismissed). Lock it in here so the field doesn't get accidentally renamed to `errorMessage` or moved behind a function.
    func testErrorIsMutableFromOutside() {
        let store = SubscriptionStore()
        store.error = "test-error"
        XCTAssertEqual(store.error, "test-error")
        store.error = nil
        XCTAssertNil(store.error)
    }

    /// Purchase with an unknown product id (not in `products`) sets a user-friendly error message and returns false. SubscriptionView relies on this for the disable-purchase-while-loading state: if it lets the tap through anyway, we show "Subscription not available yet" instead of crashing.
    func testPurchaseForUnknownProductSetsErrorAndReturnsFalse() async {
        let store = SubscriptionStore()
        let id = SubscriptionID(tier: .individual, cycle: .monthly)
        let ok = await store.purchase(id)
        XCTAssertFalse(ok)
        XCTAssertEqual(store.error, "Subscription not available yet. Try again in a moment.")
    }
}
