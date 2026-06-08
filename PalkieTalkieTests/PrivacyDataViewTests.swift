@testable import PalkieTalkie
import SwiftUI
import ViewInspector
import XCTest

@MainActor
final class PrivacyDataViewTests: XCTestCase {
    /// Two opt-in/opt-out toggles must be exposed — Personalization + Product improvement. They map 1:1 to backend's /consent endpoint fields. A refactor that collapses them or hides one silently breaks the contract.
    func testFormExposesExactlyTwoToggles() throws {
        let sut = PrivacyDataView()
        let toggles = try sut.inspect().findAll(ViewType.Toggle.self)
        XCTAssertEqual(toggles.count, 2)
    }

    /// Three NavigationLinks for the destructive/export actions exist. They're placeholders ("Coming soon") today, but the entries must be there so users see Privacy & Data is the destination for delete/export.
    func testThreeNavigationLinksForDataActionsExist() throws {
        let sut = PrivacyDataView()
        let labels = try sut.inspect().findAll(ViewType.NavigationLink.self)
        XCTAssertGreaterThanOrEqual(labels.count, 3)
    }

    /// Both toggles start at false because the .task hasn't fired yet in the inspected tree. The actual default is "load from server on first appear". Locking the pre-load state so a refactor that pre-pops them with `true` doesn't silently fake server state.
    func testTogglesStartFalseBeforeServerLoad() throws {
        let sut = PrivacyDataView()
        let toggles = try sut.inspect().findAll(ViewType.Toggle.self)
        for toggle in toggles {
            XCTAssertFalse(try toggle.isOn(), "expected toggles to start off (pre-server-load)")
        }
    }
}
