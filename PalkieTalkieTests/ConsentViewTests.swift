@testable import PalkieTalkie
import SwiftUI
import ViewInspector
import XCTest

/// Behavior tests for ConsentView (first-launch privacy gate). Per root `/CLAUDE.md` the consent screen ships with both toggles defaulting ON, no auto-accept, and a Continue button that's disabled while a save is in flight.
@MainActor
final class ConsentViewTests: XCTestCase {
    /// Both toggles default ON per `/CLAUDE.md`'s Privacy & Data spec ("both default ON but visible and flippable in one tap"). A refactor flipping them to OFF without updating the consent flow would silently change the user's first-run default.
    func testBothTogglesDefaultOn() throws {
        let sut = ConsentView(onContinue: {})
        let toggles = try sut.inspect().findAll(ViewType.Toggle.self)
        XCTAssertEqual(toggles.count, 2)
        for toggle in toggles {
            XCTAssertTrue(try toggle.isOn(), "expected both consent toggles to default ON")
        }
    }

    /// The Continue button must be present from first render — there is no "agree to terms" intermediate state. Locking this in here so a refactor that gates the button behind a precondition surfaces in CI.
    func testContinueButtonIsPresent() throws {
        let sut = ConsentView(onContinue: {})
        XCTAssertNoThrow(try sut.inspect().find(button: "Continue"))
    }
}
