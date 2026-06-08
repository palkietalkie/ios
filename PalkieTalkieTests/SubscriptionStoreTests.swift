@testable import PalkieTalkie
import XCTest

/// SubscriptionStore is a thin shell over `SubscriptionService`. Each test injects a FakeSubscriptionService that returns canned outcomes — covers every branch in loadProducts / purchase / restore / refreshEntitlement without depending on StoreKit's in-process behavior (which Xcode 26.2 doesn't reliably intercept under XCTest).
@MainActor
final class SubscriptionStoreTests: XCTestCase {
    func testInitialStateIsEmpty() {
        let store = SubscriptionStore(service: FakeSubscriptionService())
        XCTAssertTrue(store.products.isEmpty)
        XCTAssertNil(store.entitled)
        XCTAssertNil(store.error)
    }

    func testErrorIsMutableFromOutside() {
        let store = SubscriptionStore(service: FakeSubscriptionService())
        store.error = "test-error"
        XCTAssertEqual(store.error, "test-error")
        store.error = nil
        XCTAssertNil(store.error)
    }

    func testLoadProductsSucceedsAndPopulatesAllFour() async {
        let service = FakeSubscriptionService()
        service.loadResult = .success(Self.allFourProducts)
        let store = SubscriptionStore(service: service)
        await store.loadProducts()
        XCTAssertEqual(store.products.count, 4)
        for id in SubscriptionID.all {
            XCTAssertNotNil(store.products[id], "missing \(id.rawValue)")
        }
        XCTAssertNil(store.error)
    }

    func testLoadProductsErrorPathSetsErrorMessage() async {
        let service = FakeSubscriptionService()
        service.loadResult = .failure(NSError(
            domain: "test",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "simulated"],
        ))
        let store = SubscriptionStore(service: service)
        await store.loadProducts()
        XCTAssertTrue(store.products.isEmpty)
        XCTAssertEqual(store.error, "Couldn't load subscriptions. simulated")
    }

    func testLoadProductsSuccessClearsStaleError() async {
        let service = FakeSubscriptionService()
        service.loadResult = .success([:])
        let store = SubscriptionStore(service: service)
        store.error = "stale-from-prior-call"
        await store.loadProducts()
        XCTAssertNil(store.error)
    }

    func testPurchaseSuccessReturnsTrueAndRefreshes() async {
        let service = FakeSubscriptionService()
        let id = SubscriptionID(tier: .individual, cycle: .monthly)
        service.purchaseResult = .success
        service.entitlementResult = id
        let store = SubscriptionStore(service: service)
        let ok = await store.purchase(id)
        XCTAssertTrue(ok)
        XCTAssertEqual(store.entitled, id)
        XCTAssertNil(store.error)
    }

    func testPurchaseUserCancelledReturnsFalseWithoutError() async {
        let service = FakeSubscriptionService()
        service.purchaseResult = .userCancelled
        let store = SubscriptionStore(service: service)
        let ok = await store.purchase(SubscriptionID(tier: .individual, cycle: .monthly))
        XCTAssertFalse(ok)
        XCTAssertNil(store.error, "user-cancelled is not an error")
    }

    func testPurchasePendingSetsAskToBuyMessage() async {
        let service = FakeSubscriptionService()
        service.purchaseResult = .pending
        let store = SubscriptionStore(service: service)
        let ok = await store.purchase(SubscriptionID(tier: .individual, cycle: .monthly))
        XCTAssertFalse(ok)
        XCTAssertEqual(store.error, "Payment is pending approval (Ask to Buy / SCA).")
    }

    func testPurchaseUnverifiedSetsVerificationErrorMessage() async {
        let service = FakeSubscriptionService()
        service.purchaseResult = .unverified
        let store = SubscriptionStore(service: service)
        let ok = await store.purchase(SubscriptionID(tier: .individual, cycle: .monthly))
        XCTAssertFalse(ok)
        XCTAssertEqual(store.error, "Apple couldn't verify that purchase.")
    }

    func testPurchaseFailedSurfacesUnderlyingMessage() async {
        let service = FakeSubscriptionService()
        service.purchaseResult = .failed("underlying message")
        let store = SubscriptionStore(service: service)
        let ok = await store.purchase(SubscriptionID(tier: .family, cycle: .yearly))
        XCTAssertFalse(ok)
        XCTAssertEqual(store.error, "underlying message")
    }

    func testRestoreSyncsAndRefreshesEntitlement() async {
        let service = FakeSubscriptionService()
        let id = SubscriptionID(tier: .family, cycle: .yearly)
        service.entitlementResult = id
        let store = SubscriptionStore(service: service)
        await store.restore()
        XCTAssertEqual(service.syncCount, 1)
        XCTAssertEqual(store.entitled, id)
        XCTAssertNil(store.error)
    }

    func testRestoreErrorSurfacesAsError() async {
        let service = FakeSubscriptionService()
        service.syncError = NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "sync failed"])
        let store = SubscriptionStore(service: service)
        await store.restore()
        XCTAssertEqual(store.error, "sync failed")
    }

    func testRefreshEntitlementYieldsNilWhenServiceHasNone() async {
        let service = FakeSubscriptionService()
        service.entitlementResult = nil
        let store = SubscriptionStore(service: service)
        await store.refreshEntitlement()
        XCTAssertNil(store.entitled)
    }

    private static var allFourProducts: [SubscriptionID: SubscriptionProduct] {
        var dict: [SubscriptionID: SubscriptionProduct] = [:]
        for id in SubscriptionID.all {
            dict[id] = SubscriptionProduct(
                id: id,
                displayPrice: "$\(id.cycle == .monthly ? "17.99" : "83.99")",
                description: "Fake \(id.tier.rawValue) \(id.cycle.rawValue)",
            )
        }
        return dict
    }
}

final class FakeSubscriptionService: SubscriptionService, @unchecked Sendable {
    var loadResult: Result<[SubscriptionID: SubscriptionProduct], Error> = .success([:])
    var purchaseResult: PurchaseOutcome = .failed("not configured")
    var entitlementResult: SubscriptionID?
    var syncError: Error?
    private(set) var syncCount = 0
    private(set) var purchaseCalls: [SubscriptionID] = []

    func loadProducts() async throws -> [SubscriptionID: SubscriptionProduct] {
        try loadResult.get()
    }

    func purchase(_ id: SubscriptionID) async -> PurchaseOutcome {
        purchaseCalls.append(id)
        return purchaseResult
    }

    func currentEntitlement() async -> SubscriptionID? {
        entitlementResult
    }

    func sync() async throws {
        syncCount += 1
        if let err = syncError { throw err }
    }
}
