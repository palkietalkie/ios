import Foundation
import Observation

/// View-model for `OnboardingView`. Owns the language/accent selection state and the load/save logic so each is unit-testable without rendering SwiftUI.
@MainActor
@Observable
final class OnboardingViewModel {
    // Pre-filled from Clerk's name on load (firstName + lastName), editable, required. Without this the conversation prompt has no name to use and the tutor invents one. Defaulting from Clerk honors "never show an empty name field on first open".
    var preferredName: String = ""
    var languages: [LanguageDTO] = []
    var nativeLanguages: Set<String> = []
    var targetLanguage: String = "English"
    var targetAccents: Set<String> = []
    // Onboarding refinements the user sets before the primer, then persisted on save. nil/empty until picked.
    var proficiency: String?
    var tutorSpeakingSpeed: String?
    // Goals are multi-select preset slugs + an optional free-text "Other"; both fold into the single `users.goals` TEXT (comma-joined) at save time.
    var selectedGoals: Set<String> = []
    var otherGoal: String = ""
    var practiceOptions: PracticeOptionsDTO?
    var loading: Bool = true
    var saving: Bool = false
    var saveError: String?
    var loadError: String?
    var didInitialLoad: Bool = false
    /// Flag flipped after save() succeeds; the view observes and calls its onContinue closure.
    var didSaveSuccessfully: Bool = false

    /// Which wizard step is on screen. Lives here (not as view @State) so the navigation logic is unit-testable without rendering. Order is load-bearing: `displayLanguage` is first so the rest of onboarding renders in the user's chosen UI language; `proficiency`/`speed`/`goals` are mandatory refinements; `getStarted` is a no-input primer shown after the profile saves, warning the user the tutor opens the conversation first so the AI talking unprompted doesn't startle them (a real first-tester reaction).
    enum Step: Int, CaseIterable {
        case intro, displayLanguage, name, native, target, accents, proficiency, speed, goals,
             getStarted

        /// Stable wire name for the onboarding drop-off feed (sent to /onboarding/announce). Decoupled from the Int rawValue so reordering steps doesn't relabel the funnel.
        var slug: String {
            switch self {
            case .intro: "intro"
            case .displayLanguage: "displayLanguage"
            case .name: "name"
            case .native: "native"
            case .target: "target"
            case .accents: "accents"
            case .proficiency: "proficiency"
            case .speed: "speed"
            case .goals: "goals"
            case .getStarted: "getStarted"
            }
        }
    }

    var step: Step = .intro
    /// Slide direction for the view's transition: true = forward, false = back. Set by advance/goBack.
    var advancing: Bool = true
    /// First-month free-trial end date + the post-trial daily/weekly caps, fetched from /entitlement when the getStarted primer appears, so the card can say "free until <date>" and name the caps the user moves to, without iOS duplicating the backend's trial length or caps. nil when the user isn't on a trial or the fetch failed (the card is then simply hidden).
    var trialEndsAt: Date?
    var postTrialDailyMinutes: Int?
    var postTrialWeeklyMinutes: Int?

    var accentsForTargetLanguage: [String] {
        languages.first(where: { $0.name == targetLanguage })?.accents ?? []
    }

    var canContinue: Bool {
        !nativeLanguages.isEmpty && !targetAccents.isEmpty
    }

    var stepValid: Bool {
        switch step {
        case .intro: true
        case .displayLanguage: true
        case .name: !trimmedPreferredName.isEmpty
        case .native: !nativeLanguages.isEmpty
        case .target: !targetLanguage.isEmpty
        case .accents: !targetAccents.isEmpty
        case .proficiency: proficiency != nil
        case .speed: tutorSpeakingSpeed != nil
        case .goals: !selectedGoals.isEmpty || !trimmedOtherGoal.isEmpty
        case .getStarted: true
        }
    }

    var isLastStep: Bool {
        step == .getStarted
    }

    /// The last step that collects profile input (the one right before the `getStarted` primer); tapping its primary button saves, then advances to the primer. Derived from the enum order so inserting/removing steps doesn't strand this.
    var isLastInputStep: Bool {
        step.rawValue == Step.getStarted.rawValue - 1
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

    /// Required single-select: a tap sets the choice (picking another replaces it). No clear-to-nil, since the step can't be skipped.
    func pickProficiency(_ slug: String) {
        proficiency = slug
    }

    func pickSpeed(_ slug: String) {
        tutorSpeakingSpeed = slug
    }

    /// Preset goal slugs served by the backend (SSoT); empty until practice options load.
    var goalPresets: [String] {
        practiceOptions?.goals ?? []
    }

    func toggleGoal(_ slug: String) {
        if selectedGoals.contains(slug) {
            selectedGoals.remove(slug)
        } else {
            selectedGoals.insert(slug)
        }
    }

    var trimmedPreferredName: String {
        preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedOtherGoal: String {
        otherGoal.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The single `users.goals` TEXT value (see `joinGoals`): selected preset slugs + the free-text "Other".
    var goalsForSave: String {
        joinGoals(presets: goalPresets, selected: selectedGoals, other: otherGoal)
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

    func load(api: BackendAPI, auth: any Authing) async {
        loading = true
        defer { loading = false }
        // Pre-fill the name from Clerk so the name step opens with the user's real name, not blank. Only when still empty so re-entering onboarding doesn't clobber a manual edit.
        if trimmedPreferredName.isEmpty, let clerkName = await auth.preferredName {
            preferredName = clerkName
        }
        // Surface the failure instead of `try?`-swallowing it into an empty picker the user can't get past.
        do {
            languages = try await api.getLanguages()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        // Best-effort: proficiency/speed are skippable, so a failure here just shows empty lists, never blocks onboarding.
        practiceOptions = try? await api.getPracticeOptions()
    }

    func save(api: BackendAPI) async {
        saving = true
        defer { saving = false }
        let update = ProfileUpdate(
            preferredName: trimmedPreferredName.isEmpty ? nil : trimmedPreferredName,
            namePronunciation: nil,
            nativeLanguages: Array(nativeLanguages),
            targetLanguage: targetLanguage,
            targetAccents: targetAccents.isEmpty ? nil : Array(targetAccents),
            proficiency: proficiency,
            tutorSpeakingSpeed: tutorSpeakingSpeed,
            // Pre-select the correction density from the chosen proficiency (backend map); nil when proficiency is unset or options didn't load, letting the column default stand.
            correctionFrequency: proficiency.flatMap { practiceOptions?.correctionFrequencyDefaultByProficiency[$0] },
            goals: goalsForSave.isEmpty ? nil : goalsForSave,
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

    /// Pull the first-month trial's end date + post-trial caps from /entitlement (the backend owns them) so the getStarted card can celebrate "free until <date>" and name the caps the user switches to afterward. Best-effort: a non-trial user or a failed fetch just hides the card, it never blocks onboarding.
    func loadTrialInfo(api: BackendAPI) async {
        guard let entitlement = try? await api.getEntitlement(), entitlement.trialActive else { return }
        trialEndsAt = entitlement.trialEndsAt
        postTrialDailyMinutes = entitlement.freeMinutesPerDayCap
        postTrialWeeklyMinutes = entitlement.freeMinutesPerWeekCap
    }
}
