import SwiftUI

/// Practice configuration — how the user wants to learn. Split from ProfileView because target language, accents, proficiency, tutor speaking speed, and goals describe practice intent, not identity. Both views share the same `/profile` endpoint on the backend (and the same JSONCache key under the hood) — this split is iOS-side organization, not a schema change.
@MainActor
struct PracticeView: View {
    private static let profileKey = "cache.profile"
    private static let languagesKey = "cache.languages"
    private static let practiceOptionsKey = "cache.practice_options"

    @Environment(\.backendAPI) private var api
    @State private var targetLanguage: String = "English"
    @State private var targetAccents: Set<String> = []
    @State private var proficiency: String = "intermediate"
    @State private var tutorSpeakingSpeed: String = "normal"
    @State private var goals: String = ""
    @State private var languages: [LanguageDTO] = JSONCache
        .load([LanguageDTO].self, key: PracticeView.languagesKey) ?? []
    @State private var practiceOptions: PracticeOptionsDTO? = JSONCache.load(
        PracticeOptionsDTO.self,
        key: PracticeView.practiceOptionsKey,
    )
    @State private var loaded: Bool = false
    @State private var saving: Bool = false
    @State private var savedAt: Date?
    @State private var saveError: String?
    /// Guards `.task` against re-firing when the view re-appears after a NavigationLink pop. Without it, returning from MultiAccentPicker would re-run load() and clobber the user's in-progress accent selection with the unsaved server state.
    @State private var didInitialLoad: Bool = false

    init() {
        if let cached = JSONCache.load(ProfileDTO.self, key: Self.profileKey) {
            _targetLanguage = State(initialValue: cached.targetLanguage)
            _targetAccents = State(initialValue: Set(cached.targetAccents))
            _proficiency = State(initialValue: cached.proficiency)
            _tutorSpeakingSpeed = State(initialValue: cached.tutorSpeakingSpeed)
            _goals = State(initialValue: cached.goals ?? "")
            _loaded = State(initialValue: true)
        }
    }

    private var accentsForTargetLanguage: [String] {
        languages.first(where: { $0.name == targetLanguage })?.accents ?? []
    }

    /// Snake-case slug → display label ("lower_intermediate" → "Lower intermediate").
    private func display(_ slug: String) -> LocalizedStringKey {
        let words = slug.split(separator: "_").map(String.init)
        guard let first = words.first else { return LocalizedStringKey(slug) }
        let head = first.prefix(1).uppercased() + first.dropFirst().lowercased()
        let tail = words.dropFirst().map { $0.lowercased() }
        return LocalizedStringKey(([head] + tail).joined(separator: " "))
    }

    var body: some View {
        Form {
            Section("Target") {
                Picker("Language", selection: $targetLanguage) {
                    ForEach(languages) { lang in
                        Text(lang.name).tag(lang.name)
                    }
                }
                .onChange(of: targetLanguage) { _, newValue in
                    if let lang = languages.first(where: { $0.name == newValue }) {
                        targetAccents = targetAccents.intersection(lang.accents)
                    }
                }
                NavigationLink {
                    MultiAccentPicker(
                        accents: accentsForTargetLanguage,
                        selection: $targetAccents,
                    )
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
            Section("Level") {
                Picker("Proficiency", selection: $proficiency) {
                    ForEach(practiceOptions?.proficiency ?? [], id: \.self) { slug in
                        Text(display(slug)).tag(slug)
                    }
                }
                Picker("Tutor speaking speed", selection: $tutorSpeakingSpeed) {
                    ForEach(practiceOptions?.tutorSpeakingSpeed ?? [], id: \.self) { slug in
                        Text(display(slug)).tag(slug)
                    }
                }
            }
            Section {
                LabeledContent("Goals") {
                    TextField(
                        "e.g. work, travel, in-laws, pronunciation, vocabulary",
                        text: $goals,
                        axis: .vertical,
                    )
                    .multilineTextAlignment(.trailing)
                }
            } footer: {
                Text("What you're working toward. The AI uses this to steer conversation topics.")
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        if saving { ProgressView().controlSize(.small) }
                        Text(saving ? "Saving…" : "Save changes")
                        Spacer()
                        if let savedAt, Date().timeIntervalSince(savedAt) < 3 {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .labelStyle(.iconOnly)
                                .transition(.opacity)
                        }
                    }
                }
                .disabled(!loaded || saving)
                if let saveError {
                    Text(saveError).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Practice")
        .task {
            guard !didInitialLoad else { return }
            didInitialLoad = true
            await load()
        }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            async let profileTask = api.getProfile()
            async let languagesTask = api.getLanguages()
            async let practiceOptionsTask = api.getPracticeOptions()
            let profile = try await profileTask
            if let freshLanguages = try? await languagesTask {
                languages = freshLanguages
                JSONCache.save(freshLanguages, key: Self.languagesKey)
            }
            if let freshOptions = try? await practiceOptionsTask {
                practiceOptions = freshOptions
                JSONCache.save(freshOptions, key: Self.practiceOptionsKey)
            }
            targetLanguage = profile.targetLanguage
            targetAccents = Set(profile.targetAccents)
            proficiency = profile.proficiency
            tutorSpeakingSpeed = profile.tutorSpeakingSpeed
            goals = profile.goals ?? ""
            JSONCache.save(profile, key: Self.profileKey)
            loaded = true
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let update = ProfileUpdate(
            displayName: nil,
            namePronunciation: nil,
            nativeLanguages: nil,
            targetLanguage: targetLanguage,
            targetAccents: targetAccents.isEmpty ? nil : Array(targetAccents),
            proficiency: proficiency,
            tutorSpeakingSpeed: tutorSpeakingSpeed,
            goals: goals,
            locationCity: nil,
            timezone: TimeZone.current.identifier,
        )
        do {
            _ = try await api.updateProfile(update)
            saveError = nil
            withAnimation { savedAt = Date() }
            await load()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
