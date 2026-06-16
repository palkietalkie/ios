@testable import PalkieTalkie
import XCTest

final class LocalizedLanguageNameTests: XCTestCase {
    func testUnmappedNameFallsBackToItself() {
        // Constructed languages with no ISO code (and any name the backend adds that isn't in the map) degrade to the English name, never a bare code.
        XCTAssertEqual(localizedLanguageName("High Valyrian"), "High Valyrian")
        XCTAssertEqual(
            localizedLanguageName("Some Language The Backend Added Later"),
            "Some Language The Backend Added Later",
        )
    }

    func testMappedNameResolvesToANonEmptyDisplayNotTheBCPCode() {
        let display = localizedLanguageName("Japanese")
        XCTAssertFalse(display.isEmpty)
        XCTAssertNotEqual(display, "ja", "must return a human display name, not the BCP-47 code")
    }
}
