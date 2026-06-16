@testable import PalkieTalkie
import SwiftUI
import ViewInspector
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

    /// Language rows render through localizedLanguageName, not the raw backend name. Pins the display path so dropping the wrapper (which would show a bare slug under a non-English UI locale) is caught.
    func testLanguageRowsRenderLocalizedDisplay() throws {
        let sut = MultiLanguagePicker(
            languages: [LanguageDTO(name: "Japanese", accents: [])],
            selection: .constant([]),
            title: "Native languages",
        )
        let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        XCTAssertTrue(
            texts.contains(localizedLanguageName("Japanese")),
            "language row must render via localizedLanguageName; saw \(texts)",
        )
    }

    /// Accent rows render through localizedAccentName, same contract as the language rows above.
    func testAccentRowsRenderLocalizedDisplay() throws {
        let sut = MultiAccentPicker(accents: ["US General"], selection: .constant([]))
        let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        XCTAssertTrue(
            texts.contains(localizedAccentName("US General")),
            "accent row must render via localizedAccentName; saw \(texts)",
        )
    }
}
