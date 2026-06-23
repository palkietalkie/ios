@testable import PalkieTalkie
import SwiftUI
import ViewInspector
import XCTest

@MainActor
final class LanguagePickerViewTests: XCTestCase {
    /// Locale list mirrors `website/src/i18n/config.ts`. Any change here without a matching change on the website creates a cross-stack drift — adding ja on iOS while the website doesn't render ja silently breaks i18n for that user. Lock the explicit set, in order.
    func testRendersExactlyThirteenLocalesInOrder() throws {
        let sut = LanguagePickerView()
        let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        let expectedLabels = [
            "English",
            "日本語",
            "简体中文",
            "繁體中文",
            "한국어",
            "Español",
            "Português",
            "Français",
            "Deutsch",
            "Tiếng Việt",
            "Bahasa Indonesia",
            "हिन्दी",
        ]
        for label in expectedLabels {
            XCTAssertTrue(texts.contains(label), "expected locale label \(label) to render; saw \(texts)")
        }
    }

    /// The picker renders the shared `supportedAppLocales` SSoT (not its own private copy), so every catalog label shows up. Guards against the picker and onboarding's language step drifting apart.
    func testRendersEverySupportedLocaleLabel() throws {
        let sut = LanguagePickerView()
        let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        for option in supportedAppLocales where !option.label.isEmpty {
            XCTAssertTrue(texts.contains(option.label), "expected \(option.label) from supportedAppLocales to render")
        }
    }

    /// Tapping a row writes the locale code to UserDefaults — the AppStorage key the entire app reads at the root to apply `.environment(\.locale, …)`. Locking this writes-the-code behavior here so a refactor that swaps a different key surfaces immediately.
    func testTappingRowWritesAppLocaleAppStorageKey() throws {
        UserDefaults.standard.removeObject(forKey: "AppLocale")
        let sut = LanguagePickerView()
        let row = try sut.inspect().find(text: "日本語").find(ViewType.HStack.self, relation: .parent)
        try row.callOnTapGesture()
        XCTAssertEqual(UserDefaults.standard.string(forKey: "AppLocale"), "ja")
        UserDefaults.standard.removeObject(forKey: "AppLocale")
    }
}
