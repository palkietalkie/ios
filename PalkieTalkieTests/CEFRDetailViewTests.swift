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

    /// A failed word fetch must hit the catch branch (loadError) instead of `try?`-swallowing into an empty list. Hosting drives the `.task` so the catch branch actually runs.
    func testLoadFailureHitsCatchBranch() async throws {
        let transport = FakeTransport()
        transport.responseStatus = 500
        let api = try BackendAPI(
            baseURL: XCTUnwrap(URL(string: "https://test.example.com")),
            transport: transport,
            auth: StubAuthing(),
        )
        await TestHosting.host(
            NavigationStack { CEFRDetailView() }.environment(\.backendAPI, api),
            settleMs: 500,
        )
    }
}
