@testable import PalkieTalkie
import XCTest

/// `supportedAppLocales` is the single source of truth for the app's display languages, shared by `LanguagePickerView` and onboarding. Locking the set + order here: it mirrors `website/src/i18n/config.ts`, so a drift (adding a locale on iOS the website doesn't render) silently breaks i18n for that user.
final class SupportedAppLocalesTests: XCTestCase {
    func testCodesAndOrderMatchTheCatalog() {
        let codes = supportedAppLocales.map(\.code)
        XCTAssertEqual(
            codes,
            ["", "en", "ja", "zh-Hans", "zh-Hant", "ko", "es", "pt-BR", "fr", "de", "vi", "id", "hi"],
        )
    }

    func testFirstEntryIsSystemDefault() {
        XCTAssertEqual(supportedAppLocales.first?.code, "", "system default must lead so it's the no-op choice")
    }

    func testCodesAreUnique() {
        let codes = supportedAppLocales.map(\.code)
        XCTAssertEqual(Set(codes).count, codes.count, "a duplicate code would collapse two picker rows")
    }

    func testLabelsAreNativeScript() {
        let labels = Dictionary(uniqueKeysWithValues: supportedAppLocales.map { ($0.code, $0.label) })
        XCTAssertEqual(labels["ja"], "日本語")
        XCTAssertEqual(labels["ko"], "한국어")
        XCTAssertEqual(labels["hi"], "हिन्दी")
    }
}
