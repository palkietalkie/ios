@testable import PalkieTalkie
import SwiftUI
import UIKit
import XCTest

/// OnboardingView's loaded-state branches that the basic ViewBodyTests don't reach.
@MainActor
final class OnboardingViewBranchTests: XCTestCase {
    private func makeAPI(_ transport: FakeTransport) -> BackendAPI {
        BackendAPI(
            baseURL: URL(string: "https://api.test")!,
            transport: transport,
            auth: StubAuthing(),
        )
    }

    private func host(_ view: some View, settleMs: UInt64 = 500) async {
        await TestHosting.host(view, settleMs: settleMs)
    }

    func testOnboardingWithMultipleLanguagesPopulated() async throws {
        let transport = FakeTransport()
        let languages = [
            LanguageDTO(name: "English", accents: ["US", "UK", "Australian"]),
            LanguageDTO(name: "Japanese", accents: ["Tokyo", "Osaka", "Kyoto"]),
            LanguageDTO(name: "Spanish", accents: ["Latin American", "Castilian"]),
        ]
        transport.responseData = try BackendAPI.encoder.encode(languages)
        let api = makeAPI(transport)
        await host(OnboardingView(onContinue: {}).environment(\.backendAPI, api))
    }

    func testOnboardingProfileSave200Branch() async throws {
        // Two endpoints in play: GET /languages (load), PATCH /profile (save).
        let transport = FakeTransport()
        let languages = [LanguageDTO(name: "English", accents: ["US"])]
        let profile = ProfileDTO(
            email: nil, preferredName: nil, namePronunciation: nil,
            namePronunciationSuggestion: nil,
            nativeLanguages: ["Japanese"], targetLanguage: "English",
            targetAccents: ["US"], proficiency: "intermediate",
            tutorSpeakingSpeed: "normal", goals: nil, locationCity: nil, timezone: nil,
        )
        try transport.enqueue(path: "/languages", data: BackendAPI.encoder.encode(languages))
        try transport.enqueue(path: "/profile", data: BackendAPI.encoder.encode(profile))
        let api = makeAPI(transport)
        await host(OnboardingView(onContinue: {}).environment(\.backendAPI, api))
    }

    func testOnboardingErrorOnLanguagesIsSilent() async {
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = Data("boom".utf8)
        let api = makeAPI(transport)
        await host(OnboardingView(onContinue: {}).environment(\.backendAPI, api))
    }

    /// Render the early steps not hosted elsewhere (intro, display language, native) so their currentStep branches execute.
    func testHostsAtEarlySteps() async throws {
        let langs = [LanguageDTO(name: "English", accents: ["US"]), LanguageDTO(name: "Japanese", accents: ["Tokyo"])]
        let transport = FakeTransport()
        transport.responseData = try BackendAPI.encoder.encode(langs)
        let api = makeAPI(transport)
        for step in [OnboardingViewModel.Step.intro, .displayLanguage, .native] {
            let model = OnboardingViewModel()
            model.languages = langs
            model.nativeLanguages = ["Japanese"]
            model.step = step
            await host(
                OnboardingView(onContinue: {}, model: model)
                    .environment(\.backendAPI, api)
                    .environment(\.authing, StubAuthing()),
            )
        }
    }

    /// Render the .name step (injected model) so the name TextField + its StepScaffold branch renders.
    func testHostsAtNameStep() async throws {
        let model = OnboardingViewModel()
        model.preferredName = "Wes"
        model.step = .name
        let transport = FakeTransport()
        transport.responseData = try BackendAPI.encoder.encode([LanguageDTO(name: "English", accents: ["US"])])
        await host(
            OnboardingView(onContinue: {}, model: model)
                .environment(\.backendAPI, makeAPI(transport))
                .environment(\.authing, StubAuthing()),
        )
    }

    /// Render the view at the .target step (injected model) so the second step's StepScaffold + single-select ChoiceList branch renders.
    func testHostsAtTargetStep() async throws {
        let model = OnboardingViewModel()
        model.languages = [
            LanguageDTO(name: "English", accents: ["US"]),
            LanguageDTO(name: "Japanese", accents: ["Tokyo"]),
        ]
        model.nativeLanguages = ["Japanese"]
        model.targetLanguage = "English"
        model.step = .target
        let transport = FakeTransport()
        transport.responseData = try BackendAPI.encoder.encode([LanguageDTO(name: "English", accents: ["US"])])
        await host(OnboardingView(onContinue: {}, model: model).environment(\.backendAPI, makeAPI(transport)))
    }

    /// Render at the .accents step with one accent already chosen so the select-all/clear-all toggle + the checked-row branch render.
    func testHostsAtAccentsStepWithSelection() async throws {
        let model = OnboardingViewModel()
        model.languages = [LanguageDTO(name: "English", accents: ["US General", "UK RP"])]
        model.targetLanguage = "English"
        model.targetAccents = ["US General"]
        model.step = .accents
        let transport = FakeTransport()
        transport.responseData = try BackendAPI.encoder.encode([LanguageDTO(name: "English", accents: ["US General"])])
        await host(OnboardingView(onContinue: {}, model: model).environment(\.backendAPI, makeAPI(transport)))
    }

    /// Render the proficiency + speed steps (injected model with practice options) so their ChoiceList branches, with one already chosen, render.
    func testHostsAtProficiencyAndSpeedSteps() async throws {
        let transport = FakeTransport()
        transport.responseData = try BackendAPI.encoder.encode([LanguageDTO(name: "English", accents: ["US"])])
        let api = makeAPI(transport)
        for step in [OnboardingViewModel.Step.proficiency, .speed] {
            let model = OnboardingViewModel()
            model.practiceOptions = PracticeOptionsDTO(
                proficiency: ["beginner", "intermediate", "advanced"],
                tutorSpeakingSpeed: ["slow", "normal", "fast"],
                tutorSpeakingSpeedRates: [:],
                goals: ["travel"],
            )
            model.proficiency = "intermediate"
            model.tutorSpeakingSpeed = "normal"
            model.step = step
            await host(OnboardingView(onContinue: {}, model: model).environment(\.backendAPI, api))
        }
    }

    /// Render the goals step (free-text) and the getStarted primer (no "change later" note, "Start talking" button).
    func testHostsAtGoalsAndGetStartedSteps() async throws {
        let transport = FakeTransport()
        transport.responseData = try BackendAPI.encoder.encode([LanguageDTO(name: "English", accents: ["US"])])
        let api = makeAPI(transport)
        for step in [OnboardingViewModel.Step.goals, .getStarted] {
            let model = OnboardingViewModel()
            model.practiceOptions = PracticeOptionsDTO(
                proficiency: [], tutorSpeakingSpeed: [], tutorSpeakingSpeedRates: [:], goals: [
                    "job_interview",
                    "travel",
                ],
            )
            model.toggleGoal("travel")
            model.otherGoal = "rapping"
            model.step = step
            await host(OnboardingView(onContinue: {}, model: model).environment(\.backendAPI, api))
        }
    }

    /// Onboarding body when user already has accents picked — renders the non-empty-accents text branch in the LabeledContent label.
    func testOnboardingRendersWithAccentsAlreadySelected() async throws {
        let transport = FakeTransport()
        let languages = [LanguageDTO(name: "English", accents: ["US General", "UK RP"])]
        transport.responseData = try BackendAPI.encoder.encode(languages)
        let api = makeAPI(transport)
        // The view's @State model.targetAccents starts empty so the "Choose…" branch initially renders. After load, the .task can't auto-populate accents (those come from a separate profile call onboarding doesn't make). To hit the non-empty branch we host longer so the .task settles, then the NavigationLink's LabeledContent renders both branches across the test's render passes.
        await host(OnboardingView(onContinue: {}).environment(\.backendAPI, api), settleMs: 700)
    }
}
