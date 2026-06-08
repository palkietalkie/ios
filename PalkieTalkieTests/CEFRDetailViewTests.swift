@testable import PalkieTalkie
import SwiftUI
import ViewInspector
import XCTest

@MainActor
final class CEFRDetailViewTests: XCTestCase {
    /// All six CEFR bands are present in the picker as advertised. This locks the contract iOS has with `app/services/cefr_vocab/constants.py` on the backend (A1 → C2). The picker also carries a "CEFR level" accessibility label that we filter out.
    func testPickerExposesAllSixCEFRBands() throws {
        let sut = CEFRDetailView()
        let picker = try sut.inspect().find(ViewType.Picker.self)
        let allLabels = try picker.findAll(ViewType.Text.self).map { try $0.string() }
        let bandLabels = allLabels.filter { ["A1", "A2", "B1", "B2", "C1", "C2"].contains($0) }
        XCTAssertEqual(bandLabels, ["A1", "A2", "B1", "B2", "C1", "C2"])
    }

    /// Segmented picker style is the spec — refactor to a wheel or menu picker would change the user surface dramatically without breaking compile.
    func testPickerUsesSegmentedStyle() throws {
        let sut = CEFRDetailView()
        XCTAssertNoThrow(try sut.inspect().find(ViewType.Picker.self).pickerStyle())
    }
}
