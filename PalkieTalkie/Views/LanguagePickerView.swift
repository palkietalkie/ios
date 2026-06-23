import SwiftUI

/// In-app display-language picker. `@AppStorage("AppLocale")` is empty → use iOS system default; otherwise the stored BCP-47 code overrides at the root via `.environment(\.locale, …)`. Locale list is `supportedAppLocales` (shared with onboarding).
struct LanguagePickerView: View {
    @AppStorage("AppLocale") private var appLocale: String = ""

    var body: some View {
        List(supportedAppLocales, id: \.code) { item in
            HStack {
                Text(verbatim: item.label)
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
