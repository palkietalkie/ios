@testable import PalkieTalkie
import SwiftUI
import ViewInspector
import XCTest

@MainActor
final class ChoiceListTests: XCTestCase {
    /// The `display` closure maps the raw option (the selection key) to its shown label. Pin that the rendered text is the display output, not the raw key.
    func testDisplayClosureDrivesRenderedLabels() throws {
        let sut = ChoiceList(
            options: ["en", "ja"],
            isSelected: { _ in false },
            display: { $0.uppercased() },
            onTap: { _ in },
        )
        let strings = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        XCTAssertTrue(strings.contains("EN"))
        XCTAssertTrue(strings.contains("JA"))
        XCTAssertFalse(strings.contains("en"), "raw key should not render; only the display label")
    }

    /// A selected option shows the checkmark; an all-unselected list shows none.
    func testSelectedOptionShowsCheckmark() throws {
        let selected = ChoiceList(
            options: ["a", "b"], isSelected: { $0 == "b" }, onTap: { _ in },
        )
        XCTAssertNoThrow(
            try selected.inspect().find(ViewType.Image.self) { try $0.actualImage().name() == "checkmark.circle.fill" },
        )

        let none = ChoiceList(options: ["a", "b"], isSelected: { _ in false }, onTap: { _ in })
        let images = try none.inspect().findAll(ViewType.Image.self)
        XCTAssertTrue(images.isEmpty, "no checkmark when nothing is selected")
    }

    /// Tapping a row invokes onTap with that row's raw option key (not its display label).
    func testTapInvokesOnTapWithRawOption() throws {
        var tapped: String?
        let sut = ChoiceList(
            options: ["en", "ja"],
            isSelected: { _ in false },
            display: { $0.uppercased() },
            onTap: { tapped = $0 },
        )
        // Find the row whose label is "JA" and tap it; onTap must receive the raw "ja".
        let rows = try sut.inspect().findAll(ViewType.HStack.self)
        for row in rows {
            let labels = row.findAll(ViewType.Text.self).compactMap { try? $0.string() }
            if labels.contains("JA") {
                try row.callOnTapGesture()
                break
            }
        }
        XCTAssertEqual(tapped, "ja")
    }
}
