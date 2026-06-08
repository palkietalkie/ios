@testable import PalkieTalkie
import XCTest

final class SubscriptionProductsTests: XCTestCase {
    func test_allProductIDs_haveStableShape() {
        let raws = SubscriptionID.all.map(\.rawValue).sorted()
        XCTAssertEqual(
            raws,
            [
                "com.palkietalkie.family.monthly",
                "com.palkietalkie.family.yearly",
                "com.palkietalkie.individual.monthly",
                "com.palkietalkie.individual.yearly",
            ],
        )
    }

    func test_parseRawValue_roundTrip() {
        for id in SubscriptionID.all {
            let parsed = SubscriptionID(rawValue: id.rawValue)
            XCTAssertEqual(parsed, id)
        }
    }

    func test_parseRawValue_rejectsUnknown() {
        XCTAssertNil(SubscriptionID(rawValue: "com.example.individual.monthly"))
        XCTAssertNil(SubscriptionID(rawValue: "com.palkietalkie.pro.monthly"))
        XCTAssertNil(SubscriptionID(rawValue: "com.palkietalkie.individual.lifetime"))
        XCTAssertNil(SubscriptionID(rawValue: "not-a-product-id"))
    }

    func test_allRawIDs_isInSyncWithAll() {
        XCTAssertEqual(SubscriptionID.allRawIDs.count, 4)
        XCTAssertEqual(SubscriptionID.allRawIDs, Set(SubscriptionID.all.map(\.rawValue)))
    }

    /// Identifiable getters — required by ForEach to render rows. Calling each explicitly so xccov hits the getter bodies.
    func test_identifiableGettersForAllEnumCases() {
        XCTAssertEqual(SubscriptionTier.family.id, "family")
        XCTAssertEqual(SubscriptionTier.individual.id, "individual")
        XCTAssertEqual(SubscriptionCycle.monthly.id, "monthly")
        XCTAssertEqual(SubscriptionCycle.yearly.id, "yearly")
        let sid = SubscriptionID(tier: .individual, cycle: .monthly)
        XCTAssertEqual(sid.id, sid.rawValue)
    }
}
