@testable import PalkieTalkie
import XCTest

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    private func makeAPI(_ transport: FakeTransport) -> BackendAPI {
        BackendAPI(baseURL: URL(string: "https://test.example.com")!, transport: transport, auth: StubAuthing())
    }

    func testInitHasDefaults() {
        let vm = OnboardingViewModel()
        XCTAssertEqual(vm.targetLanguage, "English")
        XCTAssertTrue(vm.loading)
        XCTAssertFalse(vm.didSaveSuccessfully)
        XCTAssertFalse(vm.canContinue, "no native lang + no accent → can't continue")
    }

    func testCanContinueRequiresBoth() {
        let vm = OnboardingViewModel()
        vm.nativeLanguages = ["Japanese"]
        XCTAssertFalse(vm.canContinue)
        vm.targetAccents = ["US"]
        XCTAssertTrue(vm.canContinue)
    }

    func testAccentsForTargetLanguageReturnsMatchOrEmpty() {
        let vm = OnboardingViewModel()
        vm.languages = [LanguageDTO(name: "English", accents: ["US", "UK"])]
        vm.targetLanguage = "English"
        XCTAssertEqual(vm.accentsForTargetLanguage, ["US", "UK"])
        vm.targetLanguage = "Mandarin"
        XCTAssertEqual(vm.accentsForTargetLanguage, [])
    }

    func testFilterAccentsDropsUnsupported() {
        let vm = OnboardingViewModel()
        vm.languages = [LanguageDTO(name: "Japanese", accents: ["Tokyo"])]
        vm.targetAccents = ["US", "Tokyo"]
        vm.filterAccentsForTargetLanguage("Japanese")
        XCTAssertEqual(vm.targetAccents, ["Tokyo"])
    }

    func testFilterAccentsUnknownLanguageIsNoOp() {
        let vm = OnboardingViewModel()
        vm.languages = [LanguageDTO(name: "English", accents: ["US"])]
        vm.targetAccents = ["US"]
        vm.filterAccentsForTargetLanguage("Mandarin")
        XCTAssertEqual(vm.targetAccents, ["US"], "no-op when language unknown")
    }

    func testLoadSuccessPopulatesLanguages() async throws {
        let transport = FakeTransport()
        transport.responseData = try BackendAPI.encoder.encode([
            LanguageDTO(name: "English", accents: ["US"]),
            LanguageDTO(name: "Japanese", accents: ["Tokyo"]),
        ])
        let api = makeAPI(transport)
        let vm = OnboardingViewModel()
        await vm.load(api: api, auth: StubAuthing())
        XCTAssertEqual(vm.languages.count, 2)
        XCTAssertFalse(vm.loading)
    }

    func testLoadPrefillsNameFromClerk() async throws {
        // The fix for the "Ken" hallucination: onboarding never captured a name, so the prompt had none and the tutor invented one. Load pre-fills from Clerk so the name step opens with the real name.
        let transport = FakeTransport()
        transport.responseData = try BackendAPI.encoder.encode([LanguageDTO(name: "English", accents: ["US"])])
        let api = makeAPI(transport)
        let vm = OnboardingViewModel()
        await vm.load(api: api, auth: StubAuthing(preferredName: "Wes Nishio"))
        XCTAssertEqual(vm.preferredName, "Wes Nishio")
    }

    func testLoadDoesNotClobberEditedName() async throws {
        let transport = FakeTransport()
        transport.responseData = try BackendAPI.encoder.encode([LanguageDTO(name: "English", accents: ["US"])])
        let api = makeAPI(transport)
        let vm = OnboardingViewModel()
        vm.preferredName = "Manually Typed"
        await vm.load(api: api, auth: StubAuthing(preferredName: "Wes Nishio"))
        XCTAssertEqual(vm.preferredName, "Manually Typed", "an existing edit must survive a reload")
    }

    func testNameStepRequiresNonBlankName() {
        let vm = OnboardingViewModel()
        vm.step = .name
        XCTAssertFalse(vm.stepValid, "blank name can't advance")
        vm.preferredName = "   "
        XCTAssertFalse(vm.stepValid, "whitespace-only name is not a name")
        vm.preferredName = "Wes"
        XCTAssertTrue(vm.stepValid)
    }

    func testSaveSendsPreferredName() async throws {
        let transport = FakeTransport()
        transport.responseData = try BackendAPI.encoder.encode(
            ProfileDTO(
                email: nil, preferredName: "Wes", namePronunciation: nil,
                namePronunciationSuggestion: nil, nativeLanguages: ["Japanese"],
                targetLanguage: "English", targetAccents: ["US"], proficiency: "intermediate",
                tutorSpeakingSpeed: "normal", goals: nil, locationCity: nil, timezone: nil,
            ),
        )
        let api = makeAPI(transport)
        let vm = OnboardingViewModel()
        vm.preferredName = "  Wes  "
        await vm.save(api: api)
        let sent = try decodeProfileUpdate(transport.lastRequest?.httpBody)
        XCTAssertEqual(sent.preferredName, "Wes", "trimmed name is sent, not nil")
    }

    func testNameStepSitsBetweenDisplayLanguageAndNative() {
        // The name step must be wired into the flow in the right place, otherwise the prompt-name gap it fixes reappears.
        let vm = OnboardingViewModel()
        vm.step = .displayLanguage
        vm.advanceStep()
        XCTAssertEqual(vm.step, .name, "name comes right after display language")
        vm.preferredName = "Wes"
        vm.advanceStep()
        XCTAssertEqual(vm.step, .native, "a valid name advances to native language")
        vm.goBack()
        XCTAssertEqual(vm.step, .name, "back from native returns to the name step")
    }

    func testBlankNameCannotAdvancePastNameStep() {
        let vm = OnboardingViewModel()
        vm.step = .name
        XCTAssertFalse(vm.advanceStep(), "blank name must not advance")
        XCTAssertEqual(vm.step, .name)
    }

    func testFullSaveCarriesNameAlongsideEveryField() async throws {
        // The name must not get dropped when the rest of the profile is present — the bug was preferredName hardcoded to nil in save().
        let transport = FakeTransport()
        transport.responseData = try BackendAPI.encoder.encode(
            ProfileDTO(
                email: nil, preferredName: "Wes", namePronunciation: nil,
                namePronunciationSuggestion: nil, nativeLanguages: ["Japanese"],
                targetLanguage: "English", targetAccents: ["US"], proficiency: "advanced",
                tutorSpeakingSpeed: "fast", goals: "travel", locationCity: nil, timezone: nil,
            ),
        )
        let api = makeAPI(transport)
        let vm = OnboardingViewModel()
        vm.preferredName = "Wes"
        vm.nativeLanguages = ["Japanese"]
        vm.targetAccents = ["US"]
        vm.proficiency = "advanced"
        vm.tutorSpeakingSpeed = "fast"
        vm.practiceOptions = PracticeOptionsDTO(proficiency: [], tutorSpeakingSpeed: [], goals: ["travel"])
        vm.toggleGoal("travel")
        await vm.save(api: api)
        let sent = try decodeProfileUpdate(transport.lastRequest?.httpBody)
        XCTAssertEqual(sent.preferredName, "Wes")
        XCTAssertEqual(sent.nativeLanguages, ["Japanese"])
        XCTAssertEqual(sent.proficiency, "advanced")
        XCTAssertEqual(sent.goals, "travel")
        XCTAssertTrue(vm.didSaveSuccessfully)
    }

    func testLoadFailureSurfacesErrorNotSilentEmpty() async {
        let transport = FakeTransport()
        transport.responseStatus = 500
        let api = makeAPI(transport)
        let vm = OnboardingViewModel()
        await vm.load(api: api, auth: StubAuthing())
        XCTAssertEqual(vm.languages.count, 0)
        XCTAssertFalse(vm.loading)
        // Previously this path `try?`-swallowed the error, leaving the user stuck at an empty picker with no signal. The error must now surface.
        XCTAssertNotNil(vm.loadError)
    }

    func testSaveSuccessFlipsDidSaveSuccessfully() async throws {
        let transport = FakeTransport()
        let profile = ProfileDTO(
            email: nil,
            preferredName: nil,
            namePronunciation: nil,
            namePronunciationSuggestion: nil,
            nativeLanguages: ["Japanese"],
            targetLanguage: "English",
            targetAccents: ["US"],
            proficiency: "intermediate",
            tutorSpeakingSpeed: "normal",
            goals: nil,
            locationCity: nil,
            timezone: nil,
        )
        transport.responseData = try BackendAPI.encoder.encode(profile)
        let api = makeAPI(transport)
        let vm = OnboardingViewModel()
        vm.nativeLanguages = ["Japanese"]
        vm.targetAccents = ["US"]
        await vm.save(api: api)
        XCTAssertTrue(vm.didSaveSuccessfully)
        XCTAssertNil(vm.saveError)
    }

    func testSaveSendsProficiencySpeedGoalsWhenChosen() async throws {
        let transport = FakeTransport()
        let profile = ProfileDTO(
            email: nil,
            preferredName: nil,
            namePronunciation: nil,
            namePronunciationSuggestion: nil,
            nativeLanguages: ["Japanese"],
            targetLanguage: "English",
            targetAccents: ["US"],
            proficiency: "advanced",
            tutorSpeakingSpeed: "fast",
            goals: "work",
            locationCity: nil,
            timezone: nil,
        )
        transport.responseData = try BackendAPI.encoder.encode(profile)
        let api = makeAPI(transport)
        let vm = OnboardingViewModel()
        vm.nativeLanguages = ["Japanese"]
        vm.targetAccents = ["US"]
        vm.proficiency = "advanced"
        vm.tutorSpeakingSpeed = "fast"
        // Goals: a preset chip + a free-text "Other" fold into one comma-joined string.
        vm.practiceOptions = PracticeOptionsDTO(proficiency: [], tutorSpeakingSpeed: [], goals: ["job_interview"])
        vm.toggleGoal("job_interview")
        vm.otherGoal = "chatting with my barista"
        await vm.save(api: api)
        let sent = try decodeProfileUpdate(transport.lastRequest?.httpBody)
        XCTAssertEqual(sent.proficiency, "advanced")
        XCTAssertEqual(sent.tutorSpeakingSpeed, "fast")
        XCTAssertEqual(sent.goals, "job_interview, chatting with my barista")
    }

    func testSaveEncodesUnsetRefinementsAsNull() async throws {
        let transport = FakeTransport()
        let profile = ProfileDTO(
            email: nil,
            preferredName: nil,
            namePronunciation: nil,
            namePronunciationSuggestion: nil,
            nativeLanguages: ["Japanese"],
            targetLanguage: "English",
            targetAccents: ["US"],
            proficiency: "intermediate",
            tutorSpeakingSpeed: "normal",
            goals: nil,
            locationCity: nil,
            timezone: nil,
        )
        transport.responseData = try BackendAPI.encoder.encode(profile)
        let api = makeAPI(transport)
        let vm = OnboardingViewModel()
        vm.nativeLanguages = ["Japanese"]
        vm.targetAccents = ["US"]
        // proficiency/speed left nil, goals left empty → server defaults kept (sent as null, not a value).
        await vm.save(api: api)
        let sent = try decodeProfileUpdate(transport.lastRequest?.httpBody)
        XCTAssertNil(sent.proficiency)
        XCTAssertNil(sent.tutorSpeakingSpeed)
        XCTAssertNil(sent.goals)
    }

    /// Decode the PATCH body back into ProfileUpdate so assertions read fields by name instead of poking raw JSON keys.
    private func decodeProfileUpdate(_ body: Data?) throws -> ProfileUpdate {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ProfileUpdate.self, from: XCTUnwrap(body))
    }

    func testSaveFailureSetsSaveError() async {
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = Data("boom".utf8)
        let api = makeAPI(transport)
        let vm = OnboardingViewModel()
        await vm.save(api: api)
        XCTAssertFalse(vm.didSaveSuccessfully)
        XCTAssertNotNil(vm.saveError)
    }
}

@MainActor
final class OnboardingWizardLogicTests: XCTestCase {
    private func loadedModel() -> OnboardingViewModel {
        let vm = OnboardingViewModel()
        vm.languages = [
            LanguageDTO(name: "English", accents: ["US General", "UK RP", "Australian"]),
            LanguageDTO(name: "Japanese", accents: ["Tokyo", "Osaka"]),
        ]
        return vm
    }

    func testStepValidPerStep() {
        let vm = loadedModel()
        vm.step = .native
        XCTAssertFalse(vm.stepValid, "native step invalid with no native language")
        vm.nativeLanguages = ["Japanese"]
        XCTAssertTrue(vm.stepValid)
        vm.step = .target
        XCTAssertTrue(vm.stepValid, "target defaults to English, so valid")
        vm.step = .accents
        XCTAssertFalse(vm.stepValid, "accents step invalid with none picked")
        vm.targetAccents = ["US General"]
        XCTAssertTrue(vm.stepValid)
    }

    func testAdvanceStepBlockedWhenInvalid() {
        let vm = loadedModel()
        vm.step = .native
        XCTAssertFalse(vm.advanceStep(), "no native language → cannot advance")
        XCTAssertEqual(vm.step, .native)
    }

    func testAdvanceStepMovesForwardWhenValid() {
        let vm = loadedModel()
        vm.step = .native
        vm.nativeLanguages = ["Japanese"]
        XCTAssertTrue(vm.advanceStep())
        XCTAssertEqual(vm.step, .target)
        XCTAssertTrue(vm.advancing, "moving forward sets advancing")
    }

    func testAdvanceStepReturnsFalseOnLastStep() {
        let vm = loadedModel()
        vm.step = .getStarted
        XCTAssertFalse(vm.advanceStep(), "no step after getStarted")
        XCTAssertEqual(vm.step, .getStarted)
        XCTAssertTrue(vm.isLastStep)
    }

    func testAdvanceFromAccentsGoesToProficiencyNotSave() {
        let vm = loadedModel()
        vm.step = .accents
        vm.targetAccents = ["US General"]
        XCTAssertTrue(vm.advanceStep(), "accents now has skippable steps after it")
        XCTAssertEqual(vm.step, .proficiency)
        XCTAssertFalse(vm.isLastInputStep, "accents is no longer the save step")
    }

    func testLastInputStepIsTheStepBeforeThePrimer() {
        let vm = loadedModel()
        vm.step = .goals
        XCTAssertTrue(vm.isLastInputStep, "goals is the last data step; its button saves")
        vm.step = .accents
        XCTAssertFalse(vm.isLastInputStep)
        vm.step = .getStarted
        XCTAssertFalse(vm.isLastInputStep, "the primer isn't an input step")
    }

    func testNoInputStepsAreAlwaysValid() {
        let vm = loadedModel()
        // intro is a welcome screen; displayLanguage always has a value (system default); the primer takes no input.
        for s in [OnboardingViewModel.Step.intro, .displayLanguage, .getStarted] {
            vm.step = s
            XCTAssertTrue(vm.stepValid, "\(s) needs no choice, so always valid")
        }
    }

    func testRefinementStepsRequireAChoice() {
        let vm = loadedModel()
        vm.step = .proficiency
        XCTAssertFalse(vm.stepValid, "must pick a level to advance")
        vm.pickProficiency("intermediate")
        XCTAssertTrue(vm.stepValid)

        vm.step = .speed
        XCTAssertFalse(vm.stepValid, "must pick a speed to advance")
        vm.pickSpeed("normal")
        XCTAssertTrue(vm.stepValid)

        vm.step = .goals
        XCTAssertFalse(vm.stepValid, "must pick or type a goal to advance")
        vm.otherGoal = "   "
        XCTAssertFalse(vm.stepValid, "whitespace-only Other is not a real goal")
        vm.toggleGoal("travel")
        XCTAssertTrue(vm.stepValid, "a preset chip satisfies it")
        vm.toggleGoal("travel")
        vm.otherGoal = "rapping"
        XCTAssertTrue(vm.stepValid, "free-text Other alone satisfies it")
    }

    func testGoalsForSaveJoinsSelectedPresetsInOrderThenOther() {
        let vm = loadedModel()
        vm.practiceOptions = PracticeOptionsDTO(
            proficiency: [], tutorSpeakingSpeed: [],
            goals: ["everyday_conversation", "dating_relationships", "travel"],
        )
        vm.toggleGoal("travel")
        vm.toggleGoal("everyday_conversation")
        vm.otherGoal = "  rapping  "
        // Order follows the preset list (not tap order); the trimmed Other is appended last.
        XCTAssertEqual(vm.goalsForSave, "everyday_conversation, travel, rapping")
    }

    func testGoalsForSaveEmptyWhenNothingChosen() {
        XCTAssertEqual(loadedModel().goalsForSave, "")
    }

    func testPickProficiencyAndSpeedSetSelection() {
        let vm = loadedModel()
        vm.pickProficiency("intermediate")
        XCTAssertEqual(vm.proficiency, "intermediate")
        vm.pickProficiency("advanced")
        XCTAssertEqual(vm.proficiency, "advanced", "picking another replaces the choice")
        vm.pickSpeed("slow")
        XCTAssertEqual(vm.tutorSpeakingSpeed, "slow")
        vm.pickSpeed("fast")
        XCTAssertEqual(vm.tutorSpeakingSpeed, "fast")
    }

    func testGoBackMovesBackAndSetsDirection() {
        let vm = loadedModel()
        vm.step = .target
        vm.goBack()
        XCTAssertEqual(vm.step, .native)
        XCTAssertFalse(vm.advancing, "going back clears advancing")
    }

    func testGoBackAtFirstStepIsNoOp() {
        let vm = loadedModel()
        XCTAssertEqual(vm.step, .intro, "onboarding opens on the intro step")
        vm.goBack()
        XCTAssertEqual(vm.step, .intro)
    }

    func testToggleNativeAddsThenRemoves() {
        let vm = loadedModel()
        vm.toggleNative("Japanese")
        XCTAssertEqual(vm.nativeLanguages, ["Japanese"])
        vm.toggleNative("Japanese")
        XCTAssertTrue(vm.nativeLanguages.isEmpty)
    }

    func testPickTargetSetsLanguageAndDropsUnsupportedAccents() {
        let vm = loadedModel()
        vm.targetAccents = ["Tokyo", "US General"]
        vm.pickTarget("Japanese")
        XCTAssertEqual(vm.targetLanguage, "Japanese")
        XCTAssertEqual(vm.targetAccents, ["Tokyo"], "US General isn't a Japanese accent, so it's dropped")
    }

    func testToggleAccentAddsThenRemoves() {
        let vm = loadedModel()
        vm.toggleAccent("UK RP")
        XCTAssertEqual(vm.targetAccents, ["UK RP"])
        vm.toggleAccent("UK RP")
        XCTAssertTrue(vm.targetAccents.isEmpty)
    }

    func testToggleAllAccentsSelectsAllThenClears() {
        let vm = loadedModel() // targetLanguage defaults to English → 3 accents
        XCTAssertFalse(vm.allAccentsSelected)
        vm.toggleAllAccents()
        XCTAssertTrue(vm.allAccentsSelected)
        XCTAssertEqual(vm.targetAccents, ["US General", "UK RP", "Australian"])
        vm.toggleAllAccents()
        XCTAssertTrue(vm.targetAccents.isEmpty)
    }

    func testAllAccentsSelectedFalseWhenNoAccentsAvailable() {
        let vm = OnboardingViewModel() // no languages loaded → no accents
        XCTAssertFalse(vm.allAccentsSelected, "an empty accent set is not 'all selected'")
    }
}
