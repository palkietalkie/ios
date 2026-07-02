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
                        Text(localizedLanguageName(lang.name)).tag(lang.name)
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
                                : model.targetAccents.sorted().map(localizedAccentName).joined(separator: ", "),
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
                        Text(formatSlugLabel(slug)).tag(slug)
                    }
                }
                Picker("Tutor speaking speed", selection: $model.tutorSpeakingSpeed) {
                    ForEach(model.practiceOptions?.tutorSpeakingSpeed ?? [], id: \.self) { slug in
                        // Append the backend-sourced playback rate ("Slow · 0.85×") so the concrete number disambiguates slow vs very slow. The rate is a pure value (verbatim); the label keeps its existing rendering.
                        if let rate = model.practiceOptions?.tutorSpeakingSpeedRates[slug] {
                            (Text(formatSlugLabel(slug)) + Text(verbatim: " · \(formatSpeedRate(rate))")).tag(slug)
                        } else {
                            Text(formatSlugLabel(slug)).tag(slug)
                        }
                    }
                }
                Picker("Correction frequency", selection: $model.correctionFrequency) {
                    ForEach(model.practiceOptions?.correctionFrequency ?? [], id: \.self) { slug in
                        // Append the backend-sourced % ("Sometimes · 50%") so the level's density is concrete. The % is a pure value (verbatim).
                        if let pct = model.practiceOptions?.correctionFrequencyPercent[slug] {
                            (Text(formatSlugLabel(slug)) + Text(verbatim: " · \(pct)%")).tag(slug)
                        } else {
                            Text(formatSlugLabel(slug)).tag(slug)
                        }
                    }
                }
            }
            Section {
                ForEach(model.goalPresets, id: \.self) { slug in
                    Button {
                        model.toggleGoal(slug)
                    } label: {
                        HStack {
                            Text(verbatim: localizedGoalLabel(slug)).foregroundStyle(.primary)
                            Spacer()
                            if model.selectedGoals.contains(slug) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                TextField("Something else?", text: $model.otherGoal, axis: .vertical)
            } header: {
                Text("Goals")
            } footer: {
                Text("What you're working toward. The AI uses this to steer conversation topics.")
            }
        }
        .navigationTitle("Practice")
        .task {
            guard !model.didInitialLoad else { return }
            model.didInitialLoad = true
            await model.load(api: api)
        }
        .refreshable { await model.load(api: api) }
        // Auto-save: any edit changes the snapshot; the model debounces + guards so only real edits persist.
        .onChange(of: model.formSnapshot) { _, _ in
            model.scheduleAutoSave(api: api)
        }
    }
}
