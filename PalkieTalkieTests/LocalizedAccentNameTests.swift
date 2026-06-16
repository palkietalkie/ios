@testable import PalkieTalkie
import XCTest

final class LocalizedAccentNameTests: XCTestCase {
    func testNameWithNoCatalogEntryFallsBackToItself() {
        // A regional name with no Localizable.xcstrings entry degrades to itself, never an empty label.
        let unknown = "Totally Invented Accent 9Z"
        XCTAssertEqual(localizedAccentName(unknown), unknown)
    }

    func testReturnsNonEmptyDisplayForAKnownAccent() {
        XCTAssertFalse(localizedAccentName("US General").isEmpty)
    }
}
