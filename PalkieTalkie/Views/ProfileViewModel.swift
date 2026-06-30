import ClerkKit
import Foundation
import Observation

/// View-model for `ProfileView`. Owns editable identity + practice state plus the load / save / cache business logic so each can be unit-tested without rendering SwiftUI.
@MainActor
@Observable
final class ProfileViewModel {
    static let profileKey = "cache.profile"
    static let languagesKey = "cache.languages"
    static let practiceOptionsKey = "cache.practice_options"
    static let kgKey = "cache.knowledge_graph"

    var email: String = ""
    var preferredName: String = ""
    var namePronunciation: String = ""
    var nativeLanguages: Set<String> = []
    var targetLanguage: String = "English"
    var targetAccents: Set<String> = []
    var proficiency: String = "intermediate"
    var tutorSpeakingSpeed: String = "normal"
    var goals: String = ""
    var languages: [LanguageDTO] = []
    var practiceOptions: PracticeOptionsDTO?
    var knowledgeGraph: [KGEntityDTO] = []
    var kgError: String?
    var pronunciationSuggestion: String = ""
    var saveError: String?
    var loaded: Bool = false
    var saving: Bool = false
    var savedAt: Date?
    var didInitialLoad: Bool = false

    /// Snapshot of the editable fields. Equatable so the view can `.onChange` on it and the model can tell a real user edit from a programmatic load/re-load.
    struct FormSnapshot: Equatable {
        let preferredName: String
        let namePronunciation: String
        let nativeLanguages: Set<String>
        let targetLanguage: String
        let targetAccents: Set<String>
        let proficiency: String
        let tutorSpeakingSpeed: String
        let goals: String
    }

    var formSnapshot: FormSnapshot {
        FormSnapshot(
            preferredName: preferredName, namePronunciation: namePronunciation,
            nativeLanguages: nativeLanguages, targetLanguage: targetLanguage,
            targetAccents: targetAccents, proficiency: proficiency,
            tutorSpeakingSpeed: tutorSpeakingSpeed, goals: goals,
        )
    }

    private let autoSaver = AutoSaver<FormSnapshot>()

    init() {
        languages = JSONCache.load([LanguageDTO].self, key: Self.languagesKey) ?? []
        practiceOptions = JSONCache.load(PracticeOptionsDTO.self, key: Self.practiceOptionsKey)
        knowledgeGraph = JSONCache.load([KGEntityDTO].self, key: Self.kgKey) ?? []
        if let cached = JSONCache.load(ProfileDTO.self, key: Self.profileKey) {
            email = cached.email ?? ""
            preferredName = cached.preferredName ?? ""
            namePronunciation = cached.namePronunciation ?? ""
            nativeLanguages = Set(cached.nativeLanguages)
            targetLanguage = cached.targetLanguage
            targetAccents = Set(cached.targetAccents)
            proficiency = cached.proficiency
            tutorSpeakingSpeed = cached.tutorSpeakingSpeed
            goals = cached.goals ?? ""
            loaded = true
        }
        autoSaver.markSaved(formSnapshot)
    }

    var accentsForTargetLanguage: [String] {
        languages.first(where: { $0.name == targetLanguage })?.accents ?? []
    }

    func load(api: BackendAPI) async {
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
            preferredName = profile.preferredName ?? Self.clerkDefaultPreferredName()
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
            saveError = nil
            autoSaver.markSaved(formSnapshot)
        } catch {
            saveError = error.localizedDescription
        }
        // Surface KG load/decode failures instead of swallowing with `try?` — a silently-failed decode (the nodes/edges contract drift) is exactly how a populated KG showed up empty for real users.
        do {
            let freshKG = try await api.getKG()
            knowledgeGraph = freshKG.nodes
            JSONCache.save(freshKG.nodes, key: Self.kgKey)
            kgError = nil
        } catch {
            kgError = error.localizedDescription
        }
    }

    func save(api: BackendAPI) async {
        saving = true
        defer { saving = false }
        let update = ProfileUpdate(
            preferredName: preferredName.isEmpty ? nil : preferredName,
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
            savedAt = Date()
            autoSaver.markSaved(formSnapshot)
            // Re-fetch from backend so every cached field reflects server truth (including any fields the server normalized — e.g. accents filtered against target_language) and the on-disk cache stays in sync. The lastSavedSnapshot guard means this re-load can't bounce back into another auto-save.
            await load(api: api)
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// Auto-save on edit: replaces the manual Save button (which sat off-screen at the bottom and users forgot). Debounced so a burst of keystrokes is one PATCH, and guarded so it fires ONLY on a genuine user change — a programmatic load, the cache hydrate, or save's own re-load leave snapshot == lastSavedSnapshot and no-op, so there's no save loop. Call from the view's `.onChange(of: model.formSnapshot)`.
    func scheduleAutoSave(api: BackendAPI, debounce: Duration = .seconds(1)) {
        autoSaver.schedule(current: formSnapshot, loaded: loaded, debounce: debounce) { [weak self] in
            await self?.save(api: api)
        }
    }

    static func clerkDefaultPreferredName() -> String {
        guard let user = Clerk.shared.user else { return "" }
        // First/last only, never the email local-part (see composePreferredName) — empty is the right default when Clerk has no name.
        return composePreferredName(firstName: user.firstName, lastName: user.lastName)
    }
}
