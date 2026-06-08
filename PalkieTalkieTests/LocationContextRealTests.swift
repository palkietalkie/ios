import CoreLocation
@testable import PalkieTalkie
import XCTest

/// Real LocationContext + LocationDelegate. No CLLocationManager permission in tests, so requestOnce returns nil. Still
/// hits the early-out branches.
final class LocationContextRealTests: XCTestCase {
    func testRequestOnceReturnsNilWithoutPermission() async {
        let context = LocationContext()
        let fix = await context.requestOnce()
        XCTAssertNil(fix, "no Core Location permission in test bundle")
    }

    func testReverseGeocodeOnSimulatorReturnsSomethingOrNil() async {
        // MKReverseGeocodingRequest may resolve to nil offline; we just check the call doesn't crash.
        let context = LocationContext()
        let result = await context.reverseGeocode(LocationFix(latitude: 37.7749, longitude: -122.4194))
        // We don't assert a specific value — depends on simulator's network. Either nil or a non-empty string is fine.
        if let result {
            XCTAssertFalse(result.isEmpty)
        }
    }

    func testLocationDelegateDirectAccess() async {
        let delegate = LocationDelegate()
        // Without permission, requestOnce returns nil immediately.
        let loc = await delegate.requestOnce()
        XCTAssertNil(loc)
    }

    func testLocationDelegateRequestPermissionIsCallable() {
        let delegate = LocationDelegate()
        // No assertion possible — just confirm it doesn't crash. In a real app this triggers the iOS permission sheet.
        delegate.requestPermission()
    }

    func testLocationDelegateHandlesFailureCallback() {
        let delegate = LocationDelegate()
        let manager = CLLocationManager()
        // Direct delegate-method invocation. There's no pending continuation so the callback is a no-op — exercises the
        // guarded path.
        delegate.locationManager(manager, didFailWithError: NSError(domain: "test", code: -1))
    }

    func testLocationDelegateHandlesUpdateCallbackWithoutPending() {
        let delegate = LocationDelegate()
        let manager = CLLocationManager()
        // didUpdateLocations with no continuation: should not crash.
        let loc = CLLocation(latitude: 0, longitude: 0)
        delegate.locationManager(manager, didUpdateLocations: [loc])
    }
}
