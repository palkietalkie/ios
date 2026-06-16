@testable import PalkieTalkie
import SwiftUI
import UIKit
import ViewInspector
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

    /// A failed `/entitlement` fetch must surface (entitlementError) instead of `try?`-swallowing — otherwise the user sees the wrong plan/limits silently. Hosting with a failing backendAPI drives the entitlement `.task` branch.
    func testEntitlementLoadFailureHitsCatchBranch() async throws {
        let service = FakeSubscriptionService()
        service.loadResult = .success([:])
        let transport = FakeTransport()
        transport.responseStatus = 500
        let api = try BackendAPI(
            baseURL: XCTUnwrap(URL(string: "https://test.example.com")),
            transport: transport,
            auth: StubAuthing(),
        )
        await TestHosting.host(
            NavigationStack { SubscriptionView(service: service) }.environment(\.backendAPI, api),
            settleMs: 600,
        )
    }

    /// The price-unavailable placeholder is a plain hyphen via `Text(verbatim: "-")`, not an em dash — and no rendered copy may contain an em/en dash per `/CLAUDE.md`. Guards the dash cleanup against a regression.
    func testRenderedCopyHasNoEmOrEnDash() throws {
        let service = FakeSubscriptionService()
        let sut = SubscriptionView(service: service)
        let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        for text in texts {
            XCTAssertFalse(text.contains("—"), "em dash leaked into copy: \(text)")
            XCTAssertFalse(text.contains("–"), "en dash leaked into copy: \(text)")
        }
    }

    private static var allFour: [SubscriptionID: SubscriptionProduct] {
        var dict: [SubscriptionID: SubscriptionProduct] = [:]
        for id in SubscriptionID.all {
            dict[id] = SubscriptionProduct(id: id, displayPrice: "$X", description: "Fake product")
        }
        return dict
    }
}
