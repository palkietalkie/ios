@testable import PalkieTalkie
import SwiftUI
import XCTest

/// MultiLanguagePicker + MultiAccentPicker are subviews of OnboardingView with their own bodies + tap branches. Hosting them with seeded selection state covers the empty-set branch, the partial-selection branch (check icon visible), and the "select all" / "clear all" toolbar branches.
@MainActor
final class MultiPickerTests: XCTestCase {
    func testLanguagePickerWithEmptySelection() async {
        await TestHosting.host(NavigationStack {
            MultiLanguagePicker(
                languages: [
                    LanguageDTO(name: "English", accents: []),
                    LanguageDTO(name: "Japanese", accents: []),
                ],
                selection: .constant([]),
                title: "Native languages",
            )
        })
    }

    func testLanguagePickerWithSomeSelected() async {
        await TestHosting.host(NavigationStack {
            MultiLanguagePicker(
                languages: [
                    LanguageDTO(name: "English", accents: []),
                    LanguageDTO(name: "Japanese", accents: []),
                ],
                selection: .constant(["Japanese"]),
                title: "Native languages",
            )
        })
    }

    func testAccentPickerEmptyTriggersSelectAllToolbar() async {
        await TestHosting.host(NavigationStack {
            MultiAccentPicker(
                accents: ["US General", "UK RP", "Australian"],
                selection: .constant([]),
            )
        })
    }

    func testAccentPickerAllSelectedTriggersClearAllToolbar() async {
        let all = Set(["US General", "UK RP", "Australian"])
        await TestHosting.host(NavigationStack {
            MultiAccentPicker(
                accents: ["US General", "UK RP", "Australian"],
                selection: .constant(all),
            )
        })
    }

    func testAccentPickerPartialSelection() async {
        await TestHosting.host(NavigationStack {
            MultiAccentPicker(
                accents: ["US General", "UK RP", "Australian"],
                selection: .constant(["UK RP"]),
            )
        })
    }
}
