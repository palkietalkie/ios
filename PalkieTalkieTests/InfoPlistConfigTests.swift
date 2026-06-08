import Foundation
@testable import PalkieTalkie
import XCTest

/// Belt-and-suspenders runtime check on the keys the app reads from `Bundle.main.object(forInfoDictionaryKey:)`. The validate_info_plist.sh postGenCommand catches malformed Info.plist at `xcodegen generate` time; this catches the same class of bug at app-launch time (or under XCTest's bundle load).
///
/// The bug this exists to catch: `xcodegen generate` was run without exporting `BACKEND_URL` / `PERSONAPLEX_HOST` / `CLERK_PUBLISHABLE_KEY`, so Info.plist shipped with empty or `${VAR}`-literal values. With empty Clerk publishable key, the iOS SDK throws "Native API is disabled" on every backend call — a misleading message that pointed away from the real cause (empty config) and burned hours.
@MainActor
final class InfoPlistConfigTests: XCTestCase {
    func testClerkPublishableKeyIsConcrete() {
        let key = Bundle.main.object(forInfoDictionaryKey: "CLERK_PUBLISHABLE_KEY") as? String ?? ""
        XCTAssertFalse(key.isEmpty, "CLERK_PUBLISHABLE_KEY is empty — run boot.sh or source ios/.env before xcodegen.")
        XCTAssertFalse(key.contains("${"), "CLERK_PUBLISHABLE_KEY contains unresolved ${VAR} placeholder: \(key)")
        XCTAssertTrue(
            key.hasPrefix("pk_test_") || key.hasPrefix("pk_live_"),
            "CLERK_PUBLISHABLE_KEY does not look like a Clerk publishable key (expected pk_test_ or pk_live_): \(key)",
        )
    }

    func testBackendURLIsConcrete() {
        let url = Bundle.main.object(forInfoDictionaryKey: "BACKEND_URL") as? String ?? ""
        XCTAssertFalse(url.isEmpty, "BACKEND_URL is empty.")
        XCTAssertFalse(url.contains("${"), "BACKEND_URL contains unresolved ${VAR} placeholder: \(url)")
        XCTAssertTrue(url.hasPrefix("https://") || url.hasPrefix("http://"), "BACKEND_URL is not a URL: \(url)")
    }

    func testPersonaplexHostIsConcrete() {
        let host = Bundle.main.object(forInfoDictionaryKey: "PERSONAPLEX_HOST") as? String ?? ""
        XCTAssertFalse(host.isEmpty, "PERSONAPLEX_HOST is empty.")
        XCTAssertFalse(host.contains("${"), "PERSONAPLEX_HOST contains unresolved ${VAR} placeholder: \(host)")
        XCTAssertTrue(
            host.hasPrefix("wss://") || host.hasPrefix("ws://"),
            "PERSONAPLEX_HOST is not a websocket URL: \(host)",
        )
    }
}
