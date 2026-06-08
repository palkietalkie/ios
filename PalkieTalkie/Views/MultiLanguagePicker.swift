import SwiftUI

/// Multi-select language picker. Tap a row to toggle inclusion; selected rows show a checkmark. Used by OnboardingView + ProfileView (native languages) and PracticeView (target accents flat variant lives in MultiAccentPicker).
@MainActor
struct MultiLanguagePicker: View {
    let languages: [LanguageDTO]
    @Binding var selection: Set<String>
    let title: LocalizedStringKey

    var body: some View {
        List(languages) { lang in
            HStack {
                Text(lang.name)
                Spacer()
                if selection.contains(lang.name) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if selection.contains(lang.name) {
                    selection.remove(lang.name)
                } else {
                    selection.insert(lang.name)
                }
            }
        }
        .navigationTitle(title)
    }
}

/// Multi-select accent list. Same shape as `MultiLanguagePicker` but flat (no language nesting). At conversation start the backend picks one of the user's selected accents at random — load more for variety.
@MainActor
struct MultiAccentPicker: View {
    let accents: [String]
    @Binding var selection: Set<String>

    var body: some View {
        List(accents, id: \.self) { accent in
            HStack {
                Text(accent)
                Spacer()
                if selection.contains(accent) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if selection.contains(accent) {
                    selection.remove(accent)
                } else {
                    selection.insert(accent)
                }
            }
        }
        .navigationTitle("Target accents")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if selection.count == accents.count {
                    Button("Clear all") { selection.removeAll() }
                } else {
                    Button("Select all") { selection = Set(accents) }
                }
            }
        }
    }
}
