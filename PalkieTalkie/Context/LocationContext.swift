import CoreLocation
import Foundation
@preconcurrency import MapKit

/// Minimal location info this app cares about. Decoupled from CLLocation so tests can construct fixtures without
/// CoreLocation initializing real hardware.
struct LocationFix: Equatable {
    let latitude: Double
    let longitude: Double
}

/// One-shot location provider. Async wrapper around CLLocationManager so callers don't depend on its delegate model and
/// so we can swap a fake in tests via the `LocationProviding` protocol.
protocol LocationProviding: Sendable {
    func requestOnce() async -> LocationFix?
    func reverseGeocode(_ fix: LocationFix) async -> String?
}

/// Production implementation backed by CLLocationManager + MKReverseGeocodingRequest (CLGeocoder is deprecated as of iOS 26).
actor LocationContext: LocationProviding {
    private let delegate = LocationDelegate()

    func requestOnce() async -> LocationFix? {
        guard let location = await delegate.requestOnce() else { return nil }
        return LocationFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
        )
    }

    func reverseGeocode(_ fix: LocationFix) async -> String? {
        let location = CLLocation(latitude: fix.latitude, longitude: fix.longitude)
        return await Self.performReverseGeocode(location)
    }

    /// Nonisolated so MKReverseGeocodingRequest (non-Sendable) doesn't cross the actor boundary.
    private nonisolated static func performReverseGeocode(_ location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        let mapItems = try? await request.mapItems
        guard let shortAddress = mapItems?.first?.address?.shortAddress else { return nil }
        // iOS 26 MKAddress.shortAddress format is "City, Region" — take the locality portion.
        return shortAddress.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces)
    }
}

/// CoreLocation is delegate-based; this bridges it to async/await with a one-shot continuation. Holding the delegate on
/// the actor lets us reuse the same CLLocationManager.
final class LocationDelegate: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.delegate = self
    }

    /// Returns the device location if Location permission is already granted. Does NOT prompt the user — permission
    /// requests live behind the Integrations toggle so we don't blast users with three permission prompts on first
    /// launch.
    func requestOnce() async -> CLLocation? {
        let status = manager.authorizationStatus
        // Only proceed if already granted. .notDetermined → return nil silently; the user hasn't opted in yet via
        // Integrations.
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    /// Explicit permission request. Call this only from the Integrations toggle handler.
    func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        continuation?.resume(returning: locations.last)
        continuation = nil
    }

    func locationManager(_: CLLocationManager, didFailWithError _: Error) {
        continuation?.resume(returning: nil)
        continuation = nil
    }
}
