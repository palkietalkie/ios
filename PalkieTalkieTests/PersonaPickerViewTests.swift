@testable import PalkieTalkie
import SwiftUI
import XCTest

@MainActor
final class PersonaPickerViewTests: XCTestCase {
    /// SortOption labels are the user-visible strings in the picker. Locking them so a refactor that renames "Most liked" → "Liked" silently shifts the UI.
    func testSortOptionLabelsMatchSpec() {
        XCTAssertEqual(PersonaPickerView.SortOption.recommended.label, "Recommended")
        XCTAssertEqual(PersonaPickerView.SortOption.popular.label, "Most liked")
        XCTAssertEqual(PersonaPickerView.SortOption.recent.label, "Recent")
    }

    /// All three sort options exist as cases. A drop would silently kill a sort branch — the toolbar Picker iterates `allCases` so a missing case = a missing entry users can't reach.
    func testSortOptionAllCasesHasExactlyThree() {
        XCTAssertEqual(PersonaPickerView.SortOption.allCases.count, 3)
    }

    /// `SortOption.id == rawValue` is required by Identifiable conformance — the picker iterates `allCases` and uses the id to build the menu. A drift would compile but break the picker's selection persistence.
    func testSortOptionIdEqualsRawValue() {
        for option in PersonaPickerView.SortOption.allCases {
            XCTAssertEqual(option.id, option.rawValue)
        }
    }
}
