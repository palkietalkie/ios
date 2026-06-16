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

    /// Which wizard step is on screen. Lives here (not as view @State) so the navigation logic is unit-testable without rendering.
    enum Step: Int, CaseIterable {
        case native, target, accents
    }

    var step: Step = .native
    /// Slide direction for the view's transition: true = forward, false = back. Set by advance/goBack.
    var advancing: Bool = true

    var accentsForTargetLanguage: [String] {
        languages.first(where: { $0.name == targetLanguage })?.accents ?? []
    }

    var canContinue: Bool {
        !nativeLanguages.isEmpty && !targetAccents.isEmpty
    }

    var stepValid: Bool {
        switch step {
        case .native: !nativeLanguages.isEmpty
        case .target: !targetLanguage.isEmpty
        case .accents: !targetAccents.isEmpty
        }
    }

    var isLastStep: Bool {
        step == .accents
    }

    /// Move to the next step when the current one is valid. Returns false when already on the last step (the caller should save instead).
    @discardableResult
    func advanceStep() -> Bool {
        guard stepValid, let next = Step(rawValue: step.rawValue + 1) else { return false }
        advancing = true
        step = next
        return true
    }

    func goBack() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        advancing = false
        step = prev
    }

    func toggleNative(_ name: String) {
        if nativeLanguages.contains(name) {
            nativeLanguages.remove(name)
        } else {
            nativeLanguages.insert(name)
        }
    }

    func pickTarget(_ name: String) {
        targetLanguage = name
        filterAccentsForTargetLanguage(name)
    }

    func toggleAccent(_ name: String) {
        if targetAccents.contains(name) {
            targetAccents.remove(name)
        } else {
            targetAccents.insert(name)
        }
    }

    var allAccentsSelected: Bool {
        let all = accentsForTargetLanguage
        return !all.isEmpty && targetAccents.isSuperset(of: Set(all))
    }

    func toggleAllAccents() {
        let all = Set(accentsForTargetLanguage)
        if allAccentsSelected {
            targetAccents.subtract(all)
        } else {
            targetAccents.formUnion(all)
        }
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
            preferredName: nil,
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
