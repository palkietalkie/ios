import Foundation

/// One display-language choice: a BCP-47 code and its native-script label. `code == ""` means "follow the iOS system language".
struct AppLocaleOption: Hashable {
    let code: String
    let label: String
}

/// The app's display-language options, the single source of truth shared by `LanguagePickerView` (More → Language) and onboarding's display-language step. Mirrors `website/src/i18n/config.ts`. Labels are in native script so a user in any language can find their own without reading English.
let supportedAppLocales: [AppLocaleOption] = [
    AppLocaleOption(code: "", label: String(localized: "System default")),
    AppLocaleOption(code: "en", label: "English"),
    AppLocaleOption(code: "ja", label: "日本語"),
    AppLocaleOption(code: "zh-Hans", label: "简体中文"),
    AppLocaleOption(code: "zh-Hant", label: "繁體中文"),
    AppLocaleOption(code: "ko", label: "한국어"),
    AppLocaleOption(code: "es", label: "Español"),
    AppLocaleOption(code: "pt-BR", label: "Português"),
    AppLocaleOption(code: "fr", label: "Français"),
    AppLocaleOption(code: "de", label: "Deutsch"),
    AppLocaleOption(code: "vi", label: "Tiếng Việt"),
    AppLocaleOption(code: "id", label: "Bahasa Indonesia"),
    AppLocaleOption(code: "hi", label: "हिन्दी"),
]
