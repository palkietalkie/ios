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
    var displayName: String = ""
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
    var pronunciationSuggestion: String = ""
    var saveError: String?
    var loaded: Bool = false
    var saving: Bool = false
    var savedAt: Date?
    var didInitialLoad: Bool = false

    init() {
        languages = JSONCache.load([LanguageDTO].self, key: Self.languagesKey) ?? []
        practiceOptions = JSONCache.load(PracticeOptionsDTO.self, key: Self.practiceOptionsKey)
        knowledgeGraph = JSONCache.load([KGEntityDTO].self, key: Self.kgKey) ?? []
        if let cached = JSONCache.load(ProfileDTO.self, key: Self.profileKey) {
            email = cached.email ?? ""
            displayName = cached.displayName ?? ""
            namePronunciation = cached.namePronunciation ?? ""
            nativeLanguages = Set(cached.nativeLanguages)
            targetLanguage = cached.targetLanguage
            targetAccents = Set(cached.targetAccents)
            proficiency = cached.proficiency
            tutorSpeakingSpeed = cached.tutorSpeakingSpeed
            goals = cached.goals ?? ""
            loaded = true
        }
    }

    var accentsForTargetLanguage: [String] {
        languages.first(where: { $0.name == targetLanguage })?.accents ?? []
    }

    /// Snake-case slug → display label ("lower_intermediate" → "Lower intermediate").
    static func display(_ slug: String) -> String {
        let words = slug.split(separator: "_").map(String.init)
        guard let first = words.first else { return slug }
        let head = first.prefix(1).uppercased() + first.dropFirst().lowercased()
        let tail = words.dropFirst().map { $0.lowercased() }
        return ([head] + tail).joined(separator: " ")
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
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
        if let freshKG = try? await api.getKG() {
            knowledgeGraph = freshKG
            JSONCache.save(freshKG, key: Self.kgKey)
        }
    }

    func save(api: BackendAPI) async {
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
            savedAt = Date()
            // Re-fetch from backend so every cached field reflects server truth (including any fields the server normalized — e.g. accents filtered against target_language) and the on-disk cache stays in sync.
            await load(api: api)
        } catch {
            saveError = error.localizedDescription
        }
    }

    static func clerkDefaultDisplayName() -> String {
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
