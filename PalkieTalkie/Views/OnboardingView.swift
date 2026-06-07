import SwiftUI

/// First-launch sheet that captures `nativeLanguages`, `targetLanguage`, and `targetAccents` (multi-select) before letting the user into the main app. Other profile fields (proficiency, speaking speed, help_language, assist toggle) keep their server-side defaults and are editable later in Profile.
@MainActor
struct OnboardingView: View {
    let onContinue: () -> Void
    @Environment(\.backendAPI) private var api

    @State private var languages: [LanguageDTO] = []
    @State private var nativeLanguages: Set<String> = []
    @State private var targetLanguage: String = "English"
    @State private var targetAccents: Set<String> = []
    @State private var loading: Bool = true
    @State private var saving: Bool = false
    @State private var saveError: String?
    /// First-appearance guard so popping back from any pushed child view doesn't re-run load() and clobber the user's in-progress language / accent selections.
    @State private var didInitialLoad: Bool = false

    private var accentsForTargetLanguage: [String] {
        languages.first(where: { $0.name == targetLanguage })?.accents ?? []
    }

    private var canContinue: Bool {
        !nativeLanguages.isEmpty && !targetAccents.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("A few quick details so the AI knows how to talk to you.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section("Your native language") {
                    NavigationLink {
                        MultiLanguagePicker(
                            languages: languages,
                            selection: $nativeLanguages,
                            title: "Native languages",
                        )
                    } label: {
                        LabeledContent("Native languages") {
                            Text(nativeLanguages.isEmpty
                                ? String(localized: "Choose…")
                                : nativeLanguages.sorted().joined(separator: ", "))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                Section("Language you want to learn") {
                    Picker("Target language", selection: $targetLanguage) {
                        ForEach(languages) { lang in
                            Text(lang.name).tag(lang.name)
                        }
                    }
                    .onChange(of: targetLanguage) { _, newValue in
                        // Drop accents that don't belong to the new language (server-side validator would reject mismatches).
                        if let lang = languages.first(where: { $0.name == newValue }) {
                            targetAccents = targetAccents.intersection(lang.accents)
                        }
                    }
                }
                Section("Accents you want to practice") {
                    NavigationLink {
                        MultiAccentPicker(accents: accentsForTargetLanguage, selection: $targetAccents)
                    } label: {
                        LabeledContent("Accents") {
                            Text(
                                targetAccents.isEmpty
                                    ? String(localized: "Choose…")
                                    : targetAccents.sorted().joined(separator: ", "),
                            )
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                        }
                    }
                }
                if let saveError {
                    Section {
                        Text(saveError).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Welcome")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        Task { await save() }
                    }
                    .disabled(!canContinue || saving)
                }
            }
            .task {
                guard !didInitialLoad else { return }
                didInitialLoad = true
                await load()
            }
            .overlay {
                if loading {
                    ProgressView()
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func load() async {
        loading = true
        defer { loading = false }
        languages = await (try? api.getLanguages()) ?? []
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let update = ProfileUpdate(
            displayName: nil,
            namePronunciation: nil,
            nativeLanguages: Array(nativeLanguages),
            targetLanguage: targetLanguage,
            targetAccents: targetAccents.isEmpty ? nil : Array(targetAccents),
            proficiency: nil,
            tutorSpeakingSpeed: nil,
            goals: nil,
            locationCity: nil,
            timezone: TimeZone.current.identifier,
        )
        do {
            _ = try await api.updateProfile(update)
            onContinue()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// Multi-select language list. Tap to toggle. Used by Onboarding + Profile for `nativeLanguages` since per `/CLAUDE.md` § Ayumi requirements users can have multiple native languages (e.g. JP + a little ZH).
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
