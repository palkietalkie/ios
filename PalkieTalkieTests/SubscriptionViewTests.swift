@testable import PalkieTalkie
import StoreKit
import SwiftUI
import UIKit
import XCTest

/// SubscriptionView walks every product row from `SubscriptionID.all`, so just hosting the view in a window
/// runs the `productRow` ViewBuilder closure for all four tier×cycle combinations. StoreKit's `Product.products(for:)`
/// fails in the test bundle (no .storekit config), which exercises the "store.error" rendering branch.
@MainActor
final class SubscriptionViewTests: XCTestCase {
    private func host(_ view: some View, settleMs: UInt64 = 400) async {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: settleMs * 1_000_000)
        controller.view.layoutIfNeeded()
        window.isHidden = true
    }

    func testSubscriptionViewBody() async {
        await host(NavigationStack { SubscriptionView() }, settleMs: 600)
    }

    func testSubscriptionStoreInitDoesNotCrash() {
        let store = SubscriptionStore()
        XCTAssertNil(store.entitled)
        XCTAssertNil(store.error)
        XCTAssertTrue(store.products.isEmpty)
    }

    func testSubscriptionStoreLoadProductsErrorPath() async {
        // StoreKit returns no products outside a `.storekit` configured run; loadProducts should NOT crash and may
        // surface an error. Either branch is acceptable — what we assert is "no crash, idempotent to call again."
        let store = SubscriptionStore()
        await store.loadProducts()
        await store.loadProducts()
    }

    // `SubscriptionStore.restore()` calls `AppStore.sync()` which prompts for Apple ID auth — the test bundle has no UI
    // surface to drive it, so the call sits forever and XCTest's watchdog SIGKILLs the process. We can't cover that
    // path without a real `.storekit` configuration file. Leaving it explicitly uncovered here.

    func testSubscriptionStorePurchaseWithoutProductSetsError() async {
        let store = SubscriptionStore()
        let id = SubscriptionID(tier: .individual, cycle: .monthly)
        let ok = await store.purchase(id)
        XCTAssertFalse(ok)
        XCTAssertNotNil(store.error)
    }

    func testSubscriptionStoreRefreshEntitlementYieldsNil() async {
        let store = SubscriptionStore()
        await store.refreshEntitlement()
        XCTAssertNil(store.entitled)
    }
}
