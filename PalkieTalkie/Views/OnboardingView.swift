import SwiftUI

/// First-launch sheet that captures `nativeLanguages`, `targetLanguage`, and `targetAccents` (multi-select) before letting the user into the main app. Other profile fields (proficiency, speaking speed, help_language, assist toggle) keep their server-side defaults and are editable later in Profile.
@MainActor
struct OnboardingView: View {
    let onContinue: () -> Void
    @Environment(\.backendAPI) private var api
    @State private var model = OnboardingViewModel()

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
                            languages: model.languages,
                            selection: $model.nativeLanguages,
                            title: "Native languages",
                        )
                    } label: {
                        LabeledContent("Native languages") {
                            Text(model.nativeLanguages.isEmpty
                                ? String(localized: "Choose…")
                                : model.nativeLanguages.sorted().joined(separator: ", "))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                Section("Language you want to learn") {
                    Picker("Target language", selection: $model.targetLanguage) {
                        ForEach(model.languages) { lang in
                            Text(lang.name).tag(lang.name)
                        }
                    }
                    .onChange(of: model.targetLanguage) { _, newValue in
                        model.filterAccentsForTargetLanguage(newValue)
                    }
                }
                Section("Accents you want to practice") {
                    NavigationLink {
                        MultiAccentPicker(accents: model.accentsForTargetLanguage, selection: $model.targetAccents)
                    } label: {
                        LabeledContent("Accents") {
                            Text(
                                model.targetAccents.isEmpty
                                    ? String(localized: "Choose…")
                                    : model.targetAccents.sorted().joined(separator: ", "),
                            )
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                        }
                    }
                }
                if let loadError = model.loadError {
                    Section {
                        Text("Couldn't load languages: \(loadError)")
                            .font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                if let saveError = model.saveError {
                    Section {
                        Text(saveError).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Welcome")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        Task { await model.save(api: api) }
                    }
                    .disabled(!model.canContinue || model.saving)
                }
            }
            .task {
                guard !model.didInitialLoad else { return }
                model.didInitialLoad = true
                await model.load(api: api)
            }
            .overlay {
                if model.loading {
                    ProgressView()
                }
            }
            .onChange(of: model.didSaveSuccessfully) { _, newValue in
                if newValue { onContinue() }
            }
        }
        .interactiveDismissDisabled()
    }
}
