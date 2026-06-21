@testable import PalkieTalkie
import XCTest

final class GoalsCodecTests: XCTestCase {
    private let presets = ["everyday_conversation", "dating_relationships", "travel"]

    func testJoinOrdersByPresetThenAppendsTrimmedOther() {
        let joined = joinGoals(presets: presets, selected: ["travel", "everyday_conversation"], other: "  rapping  ")
        XCTAssertEqual(joined, "everyday_conversation, travel, rapping")
    }

    func testJoinEmptyWhenNothingChosen() {
        XCTAssertEqual(joinGoals(presets: presets, selected: [], other: "   "), "")
    }

    func testJoinOtherOnly() {
        XCTAssertEqual(joinGoals(presets: presets, selected: [], other: "rapping"), "rapping")
    }

    func testSplitSeparatesPresetsFromOther() {
        let result = splitGoals("dating_relationships, travel, chatting with my barista", presets: presets)
        XCTAssertEqual(result.selected, ["dating_relationships", "travel"])
        XCTAssertEqual(result.other, "chatting with my barista")
    }

    func testSplitRoundTripsOtherWithAComma() {
        // A free-text Other containing a comma must come back intact (only exact preset tokens are pulled out).
        let raw = joinGoals(presets: presets, selected: ["travel"], other: "work, life, everything")
        let back = splitGoals(raw, presets: presets)
        XCTAssertEqual(back.selected, ["travel"])
        XCTAssertEqual(back.other, "work, life, everything")
    }

    func testSplitLegacyFreeTextBecomesOther() {
        // Pre-migration goals were free text; with none matching a preset they all land in Other.
        let result = splitGoals("improve my accent", presets: presets)
        XCTAssertTrue(result.selected.isEmpty)
        XCTAssertEqual(result.other, "improve my accent")
    }
}
