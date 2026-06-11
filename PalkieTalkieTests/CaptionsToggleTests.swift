@testable import PalkieTalkie
import SwiftUI
import ViewInspector
import XCTest

/// The CC button is monochrome, YouTube-style: filled when captions are enabled, hollow when disabled, with no brand color and no underline. These lock that visual contract so a future tweak can't quietly reintroduce the blue pill or an under-bar.
@MainActor
final class CaptionsToggleTests: XCTestCase {
    func testFilledOnlyWhenEnabled() {
        XCTAssertEqual(CaptionsToggle.fill(enabled: false), Color.clear, "disabled CC must be hollow — no fill")
        XCTAssertNotEqual(CaptionsToggle.fill(enabled: true), Color.clear, "enabled CC must be filled")
    }

    func testNeverUsesBrandColor() {
        for enabled in [true, false] {
            XCTAssertNotEqual(CaptionsToggle.fill(enabled: enabled), Color.blue)
            XCTAssertNotEqual(CaptionsToggle.foreground(enabled: enabled), Color.blue)
        }
    }

    func testBrightnessAndFillDifferByState() {
        XCTAssertNotEqual(
            CaptionsToggle.foreground(enabled: true), CaptionsToggle.foreground(enabled: false),
            "enabled vs disabled must differ in brightness",
        )
        XCTAssertNotEqual(
            CaptionsToggle.fill(enabled: true), CaptionsToggle.fill(enabled: false),
            "enabled vs disabled must differ in fill",
        )
    }

    func testHasNoUnderlineBar() throws {
        let sut = CaptionsToggle(enabled: .constant(true))
        // No under-bar means the button's label is the "CC" Text itself. The earlier under-bar version stacked the text above a Rectangle in a VStack, which would make `.text()` on the label throw.
        let label = try sut.inspect().find(ViewType.Button.self).labelView()
        XCTAssertEqual(try label.text().string(), "CC", "CC label must be a plain Text, not a stack with an under-bar")
    }
}
