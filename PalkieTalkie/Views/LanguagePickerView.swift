import SwiftUI

/// In-app display-language picker. `@AppStorage("AppLocale")` is empty → use iOS system default; otherwise the stored BCP-47 code overrides at the root via `.environment(\.locale, …)`. Locale list mirrors `website/src/i18n/config.ts`.
struct LanguagePickerView: View {
    @AppStorage("AppLocale") private var appLocale: String = ""

    /// (code, native-script label). Native-script so a user in any language can pick their own without needing to read English.
    private let locales: [(code: String, label: String)] = [
        ("", String(localized: "System default")),
        ("en", "English"),
        ("ja", "日本語"),
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文"),
        ("ko", "한국어"),
        ("es", "Español"),
        ("pt-BR", "Português"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("vi", "Tiếng Việt"),
        ("id", "Bahasa Indonesia"),
        ("hi", "हिन्दी"),
    ]

    var body: some View {
        List(locales, id: \.code) { item in
            HStack {
                Text(item.label)
                Spacer()
                if appLocale == item.code {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { appLocale = item.code }
        }
        .navigationTitle("Display language")
    }
}
