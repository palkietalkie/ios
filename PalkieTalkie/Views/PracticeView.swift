import SwiftUI

/// Practice configuration — how the user wants to learn. Split from ProfileView because target language, accents, proficiency, tutor speaking speed, and goals describe practice intent, not identity. Both views share the same `/profile` endpoint on the backend (and the same JSONCache key under the hood) — this split is iOS-side organization, not a schema change.
@MainActor
struct PracticeView: View {
    @Environment(\.backendAPI) private var api
    @State private var model = PracticeViewModel()

    var body: some View {
        Form {
            Section("Target") {
                Picker("Language", selection: $model.targetLanguage) {
                    ForEach(model.languages) { lang in
                        Text(lang.name).tag(lang.name)
                    }
                }
                .onChange(of: model.targetLanguage) { _, newValue in
                    model.filterAccentsForTargetLanguage(newValue)
                }
                NavigationLink {
                    MultiAccentPicker(
                        accents: model.accentsForTargetLanguage,
                        selection: $model.targetAccents,
                    )
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
            Section("Level") {
                Picker("Proficiency", selection: $model.proficiency) {
                    ForEach(model.practiceOptions?.proficiency ?? [], id: \.self) { slug in
                        Text(PracticeViewModel.display(slug)).tag(slug)
                    }
                }
                Picker("Tutor speaking speed", selection: $model.tutorSpeakingSpeed) {
                    ForEach(model.practiceOptions?.tutorSpeakingSpeed ?? [], id: \.self) { slug in
                        Text(PracticeViewModel.display(slug)).tag(slug)
                    }
                }
            }
            Section {
                LabeledContent("Goals") {
                    TextField(
                        "e.g. work, travel, in-laws, pronunciation, vocabulary",
                        text: $model.goals,
                        axis: .vertical,
                    )
                    .multilineTextAlignment(.trailing)
                }
            } footer: {
                Text("What you're working toward. The AI uses this to steer conversation topics.")
            }
            Section {
                Button {
                    Task { await model.save(api: api) }
                } label: {
                    HStack {
                        if model.saving { ProgressView().controlSize(.small) }
                        Text(model.saving ? "Saving…" : "Save changes")
                        Spacer()
                        if let savedAt = model.savedAt, Date().timeIntervalSince(savedAt) < 3 {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .labelStyle(.iconOnly)
                                .transition(.opacity)
                        }
                    }
                    // View-side animation so the VM stays SwiftUI-agnostic and safe to unit-test outside a render context.
                    .animation(.default, value: model.savedAt)
                }
                .disabled(!model.loaded || model.saving)
                if let saveError = model.saveError {
                    Text(saveError).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Practice")
        .task {
            guard !model.didInitialLoad else { return }
            model.didInitialLoad = true
            await model.load(api: api)
        }
        .refreshable { await model.load(api: api) }
    }
}
