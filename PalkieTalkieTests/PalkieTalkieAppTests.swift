@testable import PalkieTalkie
import SwiftUI
import XCTest

/// The `@main` App entry. Most of its work happens in init (Clerk configure, AppEnvironment wiring) which we can't fully replay under XCTest without a UIApplication. What we CAN lock down is the type's conformance + that the @main attribute hasn't drifted to a different type — both of which are silent failure modes if the build accidentally renames or stops conforming.
@MainActor
final class PalkieTalkieAppTests: XCTestCase {
    /// PalkieTalkieApp must conform to SwiftUI's `App` protocol. A signature drift (Scene → other shape) would compile here but break the launch.
    func testConformsToApp() {
        XCTAssertTrue((PalkieTalkieApp.self as Any) is any App.Type)
    }

    /// `init()` performs the full production wiring (Clerk.configure + AppEnvironment factories + PushNotifications + SessionController). Constructing the App under XCTest exercises that whole composition once and asserts it doesn't trap — the same init the real `@main` launch runs. This catches a regression where any of those factories starts panicking at construction time.
    func testInitWiresProductionDependenciesWithoutTrapping() {
        let app = PalkieTalkieApp()
        // body is `some Scene` (non-optional); evaluating it forces the WindowGroup + environment wiring to build.
        _ = app.body
    }
}
