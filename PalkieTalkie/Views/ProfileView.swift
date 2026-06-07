import ClerkKit
import SwiftUI

@MainActor
struct ProfileView: View {
    private static let profileKey = "cache.profile"
    private static let languagesKey = "cache.languages"
    private static let practiceOptionsKey = "cache.practice_options"
    private static let kgKey = "cache.knowledge_graph"

    @Environment(\.backendAPI) private var api
    @Environment(\.authing) private var auth
    @State private var email: String = ""
    @State private var displayName: String = ""
    @State private var namePronunciation: String = ""
    @State private var nativeLanguages: Set<String> = []
    @State private var targetLanguage: String = "English"
    @State private var targetAccents: Set<String> = []
    @State private var proficiency: String = "intermediate"
    @State private var tutorSpeakingSpeed: String = "normal"
    @State private var goals: String = ""
    @State private var languages: [LanguageDTO] = JSONCache
        .load([LanguageDTO].self, key: ProfileView.languagesKey) ?? []
    @State private var practiceOptions: PracticeOptionsDTO? = JSONCache.load(
        PracticeOptionsDTO.self,
        key: ProfileView.practiceOptionsKey,
    )
    @State private var knowledgeGraph: [KGEntityDTO] = JSONCache.load([KGEntityDTO].self, key: ProfileView.kgKey) ?? []
    @State private var saveError: String?
    @State private var loaded: Bool = false
    @State private var saving: Bool = false
    @State private var savedAt: Date?
    /// First-appearance guard for `.task`. Without it, popping back from any pushed child view re-fires load() and clobbers in-progress edits with unsaved server state.
    @State private var didInitialLoad: Bool = false
    /// Server-suggested pronunciation shown as a TextField placeholder when the user hasn't typed one. Never persisted — only the user typing into the field writes anything to the backend.
    @State private var pronunciationSuggestion: String = ""

    init() {
        if let cached = JSONCache.load(ProfileDTO.self, key: Self.profileKey) {
            _email = State(initialValue: cached.email ?? "")
            _displayName = State(initialValue: cached.displayName ?? "")
            _namePronunciation = State(initialValue: cached.namePronunciation ?? "")
            _nativeLanguages = State(initialValue: Set(cached.nativeLanguages))
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

    /// Snake-case slug → display label ("lower_intermediate" → "Lower intermediate"). The result lines up with the keys in `Localizable.xcstrings`, so `Text(LocalizedStringKey(slug.profileOptionDisplay))` localizes.
    private func display(_ slug: String) -> LocalizedStringKey {
        let words = slug.split(separator: "_").map(String.init)
        guard let first = words.first else { return LocalizedStringKey(slug) }
        let head = first.prefix(1).uppercased() + first.dropFirst().lowercased()
        let tail = words.dropFirst().map { $0.lowercased() }
        return LocalizedStringKey(([head] + tail).joined(separator: " "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    LabeledContent("Email") {
                        Text(email.isEmpty
                            ? (Clerk.shared.user?.primaryEmailAddress?.emailAddress ?? "—")
                            : email)
                    }
                    LabeledContent("Preferred name") {
                        TextField("e.g. Wes", text: $displayName)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Pronunciation") {
                        TextField("e.g. WESS", text: $namePronunciation)
                            .multilineTextAlignment(.trailing)
                    }
                    // Distinct sub-row so the user can clearly tell this is a SUGGESTION (not the stored value) and tap to accept. Ghost-text placeholder reads identically to a real value to most users.
                    if namePronunciation.isEmpty, !pronunciationSuggestion.isEmpty {
                        Button {
                            namePronunciation = pronunciationSuggestion
                        } label: {
                            HStack {
                                Text("Suggested:").foregroundStyle(.secondary)
                                Text(pronunciationSuggestion).bold()
                                Spacer()
                                Text("Tap to use").font(.caption).foregroundStyle(.tint)
                            }
                        }
                        .buttonStyle(.plain)
                    }
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
                Section("Knowledge Graph (read-only)") {
                    if knowledgeGraph.isEmpty {
                        Text(
                            "No entities yet. As you talk, the AI starts recognizing the people, places, and projects.",
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    } else {
                        ForEach(knowledgeGraph, id: \.id) { entity in
                            VStack(alignment: .leading) {
                                Text(entity.name).font(.headline)
                                Text(entity.type.capitalized).font(.caption).foregroundStyle(.secondary)
                                ForEach(entity.attrs.sorted(by: { $0.key < $1.key }), id: \.key) { pair in
                                    Text("\(pair.key): \(pair.value)").font(.caption2)
                                }
                            }
                        }
                    }
                }
                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            if saving {
                                ProgressView().controlSize(.small)
                            }
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
                Section {
                    Button("Sign out", role: .destructive) {
                        let auth = auth
                        Task { await auth.signOut() }
                    }
                }
            }
            .navigationTitle("Profile")
            .task {
                guard !didInitialLoad else { return }
                didInitialLoad = true
                await load()
            }
            .refreshable { await load() }
        }
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
            email = profile.email ?? ""
            displayName = profile.displayName ?? Self.clerkDefaultDisplayName()
            namePronunciation = profile.namePronunciation ?? ""
            pronunciationSuggestion = profile.namePronunciationSuggestion ?? ""
            nativeLanguages = Set(profile.nativeLanguages)
            targetLanguage = profile.targetLanguage
            targetAccents = Set(profile.targetAccents)
            proficiency = profile.proficiency
            tutorSpeakingSpeed = profile.tutorSpeakingSpeed
            goals = profile.goals ?? ""
            JSONCache.save(profile, key: Self.profileKey)
            loaded = true
        } catch {
            saveError = error.localizedDescription
        }
        if let freshKG = try? await api.getKG() {
            knowledgeGraph = freshKG
            JSONCache.save(freshKG, key: Self.kgKey)
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let update = ProfileUpdate(
            displayName: displayName.isEmpty ? nil : displayName,
            // Send the actual value, even if empty. The user clearing the field IS the intent — the backend's COALESCE PATCH semantics treat `null` as "keep existing", so the only way to persist a clear is to send the empty string explicitly.
            namePronunciation: namePronunciation,
            nativeLanguages: nativeLanguages.isEmpty ? nil : Array(nativeLanguages),
            targetLanguage: targetLanguage,
            targetAccents: targetAccents.isEmpty ? nil : Array(targetAccents),
            proficiency: proficiency,
            tutorSpeakingSpeed: tutorSpeakingSpeed,
            goals: goals.isEmpty ? nil : goals,
            locationCity: nil,
            timezone: TimeZone.current.identifier,
        )
        do {
            _ = try await api.updateProfile(update)
            saveError = nil
            withAnimation { savedAt = Date() }
            // Re-fetch from backend so every cached field reflects server truth (including any fields the server normalized — e.g. accents filtered against target_language) and the on-disk cache stays in sync. Previously, only the user's local @State was updated, so leaving and re-entering the view could briefly show stale values before .task refreshed.
            await load()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private static func clerkDefaultDisplayName() -> String {
        guard let user = Clerk.shared.user else { return "" }
        if let first = user.firstName, !first.isEmpty { return first }
        let firstPart = user.firstName ?? ""
        let lastPart = user.lastName ?? ""
        let full = [firstPart, lastPart].filter { !$0.isEmpty }.joined(separator: " ")
        if !full.isEmpty { return full }
        if let email = user.primaryEmailAddress?.emailAddress {
            return String(email.prefix(while: { $0 != "@" }))
        }
        return ""
    }
}
