import Foundation
import Observation

/// View-model for `PracticeView`. Owns target / level / goals state + load/save business logic so each can be unit-tested without rendering SwiftUI.
@MainActor
@Observable
final class PracticeViewModel {
    static let profileKey = "cache.profile"
    static let languagesKey = "cache.languages"
    static let practiceOptionsKey = "cache.practice_options"

    var targetLanguage: String = "English"
    var targetAccents: Set<String> = []
    var proficiency: String = "intermediate"
    var tutorSpeakingSpeed: String = "normal"
    var goals: String = ""
    var languages: [LanguageDTO] = []
    var practiceOptions: PracticeOptionsDTO?
    var loaded: Bool = false
    var saving: Bool = false
    var savedAt: Date?
    var saveError: String?
    var didInitialLoad: Bool = false

    init() {
        languages = JSONCache.load([LanguageDTO].self, key: Self.languagesKey) ?? []
        practiceOptions = JSONCache.load(PracticeOptionsDTO.self, key: Self.practiceOptionsKey)
        if let cached = JSONCache.load(ProfileDTO.self, key: Self.profileKey) {
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

    func save(api: BackendAPI) async {
        saving = true
        defer { saving = false }
        let update = ProfileUpdate(
            preferredName: nil,
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
            savedAt = Date()
            await load(api: api)
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// Drop accents the new target language doesn't support. Called from the view's onChange(of: targetLanguage).
    func filterAccentsForTargetLanguage(_ newValue: String) {
        if let lang = languages.first(where: { $0.name == newValue }) {
            targetAccents = targetAccents.intersection(lang.accents)
        }
    }
}
