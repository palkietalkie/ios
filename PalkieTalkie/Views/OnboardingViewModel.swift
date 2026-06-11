import Foundation
import Observation

/// View-model for `OnboardingView`. Owns the language/accent selection state and the load/save logic so each is unit-testable without rendering SwiftUI.
@MainActor
@Observable
final class OnboardingViewModel {
    var languages: [LanguageDTO] = []
    var nativeLanguages: Set<String> = []
    var targetLanguage: String = "English"
    var targetAccents: Set<String> = []
    var loading: Bool = true
    var saving: Bool = false
    var saveError: String?
    var loadError: String?
    var didInitialLoad: Bool = false
    /// Flag flipped after save() succeeds; the view observes and calls its onContinue closure.
    var didSaveSuccessfully: Bool = false

    var accentsForTargetLanguage: [String] {
        languages.first(where: { $0.name == targetLanguage })?.accents ?? []
    }

    var canContinue: Bool {
        !nativeLanguages.isEmpty && !targetAccents.isEmpty
    }

    func filterAccentsForTargetLanguage(_ newValue: String) {
        if let lang = languages.first(where: { $0.name == newValue }) {
            targetAccents = targetAccents.intersection(lang.accents)
        }
    }

    func load(api: BackendAPI) async {
        loading = true
        defer { loading = false }
        // Surface the failure instead of `try?`-swallowing it into an empty picker the user can't get past.
        do {
            languages = try await api.getLanguages()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func save(api: BackendAPI) async {
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
            didSaveSuccessfully = true
        } catch {
            saveError = error.localizedDescription
        }
    }
}
