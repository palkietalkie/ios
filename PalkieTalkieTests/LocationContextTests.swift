@testable import PalkieTalkie
import XCTest

/// In-memory location provider that replaces the CLLocationManager-backed one in tests. Lets `ContextGatherer` be exercised without permission prompts.
actor FakeLocationProvider: LocationProviding {
    var fix: LocationFix?
    var city: String?

    init(fix: LocationFix? = nil, city: String? = nil) {
        self.fix = fix
        self.city = city
    }

    func requestOnce() async -> LocationFix? {
        fix
    }

    func reverseGeocode(_: LocationFix) async -> String? {
        city
    }
}

final class LocationContextTests: XCTestCase {
    func testPermissionDeniedReturnsNil() async {
        let provider = FakeLocationProvider(fix: nil)
        let fix = await provider.requestOnce()
        XCTAssertNil(fix)
    }

    func testLocationFixReceived() async {
        let provider = FakeLocationProvider(
            fix: LocationFix(latitude: 37.77, longitude: -122.42),
            city: "San Francisco",
        )
        let fix = await provider.requestOnce()
        XCTAssertEqual(fix?.latitude, 37.77)
        XCTAssertEqual(fix?.longitude, -122.42)
    }

    func testReverseGeocodeReturnsCity() async {
        let provider = FakeLocationProvider(
            fix: LocationFix(latitude: 1, longitude: 2),
            city: "Tokyo",
        )
        let city = await provider.reverseGeocode(LocationFix(latitude: 1, longitude: 2))
        XCTAssertEqual(city, "Tokyo")
    }
}
