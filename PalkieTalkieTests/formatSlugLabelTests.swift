@testable import PalkieTalkie
import XCTest

final class formatSlugLabelTests: XCTestCase {
    func testTitleCasesSnakeCaseSlug() {
        XCTAssertEqual(formatSlugLabel("lower_intermediate"), "Lower intermediate")
        XCTAssertEqual(formatSlugLabel("beginner"), "Beginner")
        XCTAssertEqual(formatSlugLabel("very_fast"), "Very fast")
    }

    func testEmptyStringReturnsItself() {
        XCTAssertEqual(formatSlugLabel(""), "")
    }
}
