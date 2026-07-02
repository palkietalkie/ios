@testable import PalkieTalkie
import XCTest

final class FormatSpeedRateTests: XCTestCase {
    func testDropsTrailingZeros() {
        XCTAssertEqual(formatSpeedRate(1.0), "1×")
        XCTAssertEqual(formatSpeedRate(0.7), "0.7×")
        XCTAssertEqual(formatSpeedRate(0.85), "0.85×")
        XCTAssertEqual(formatSpeedRate(1.15), "1.15×")
        XCTAssertEqual(formatSpeedRate(1.3), "1.3×")
    }

    func testDistinctRatesRenderDistinctly() {
        // The whole point: "slow" vs "very slow" must read differently once the number is shown.
        XCTAssertNotEqual(formatSpeedRate(0.7), formatSpeedRate(0.85))
    }
}
