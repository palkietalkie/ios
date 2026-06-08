@testable import PalkieTalkie
import SwiftUI
import UIKit
import XCTest

/// Hosts SubscriptionView with an injected FakeSubscriptionService so every body branch actually runs — products-loaded upgrade rows, current-plan-entitled section, error footer, purchase progress states. Without the seam, in-process XCTest can't drive these branches because Apple's `Product.products(for:)` returns empty under Xcode 26.2's CLI test runner.
@MainActor
final class SubscriptionViewTests: XCTestCase {
    func testRendersFreePlanAndUpgradesUnavailableWhenServiceReturnsEmpty() async {
        let service = FakeSubscriptionService()
        service.loadResult = .success([:])
        await TestHosting.host(NavigationStack { SubscriptionView(service: service) }, settleMs: 600)
    }

    func testRendersUpgradeRowsForAllFourProducts() async {
        let service = FakeSubscriptionService()
        service.loadResult = .success(Self.allFour)
        await TestHosting.host(NavigationStack { SubscriptionView(service: service) }, settleMs: 600)
    }

    func testRendersCurrentPlanWhenUserIsEntitled() async {
        let service = FakeSubscriptionService()
        service.loadResult = .success(Self.allFour)
        service.entitlementResult = SubscriptionID(tier: .individual, cycle: .yearly)
        await TestHosting.host(NavigationStack { SubscriptionView(service: service) }, settleMs: 600)
    }

    func testRendersErrorFooterWhenLoadFails() async {
        let service = FakeSubscriptionService()
        service.loadResult = .failure(NSError(
            domain: "test",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "synthetic"],
        ))
        await TestHosting.host(NavigationStack { SubscriptionView(service: service) }, settleMs: 600)
    }

    func testRendersFamilyTierAsCurrentEntitlement() async {
        let service = FakeSubscriptionService()
        service.loadResult = .success(Self.allFour)
        service.entitlementResult = SubscriptionID(tier: .family, cycle: .monthly)
        await TestHosting.host(NavigationStack { SubscriptionView(service: service) }, settleMs: 600)
    }

    private static var allFour: [SubscriptionID: SubscriptionProduct] {
        var dict: [SubscriptionID: SubscriptionProduct] = [:]
        for id in SubscriptionID.all {
            dict[id] = SubscriptionProduct(id: id, displayPrice: "$X", description: "Fake product")
        }
        return dict
    }
}
