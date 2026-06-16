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
        await vm.load(api: api)
        XCTAssertEqual(vm.languages.count, 2)
        XCTAssertFalse(vm.loading)
    }

    func testLoadFailureSurfacesErrorNotSilentEmpty() async {
        let transport = FakeTransport()
        transport.responseStatus = 500
        let api = makeAPI(transport)
        let vm = OnboardingViewModel()
        await vm.load(api: api)
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
        XCTAssertFalse(vm.advanceStep(), "no native language → cannot advance")
        XCTAssertEqual(vm.step, .native)
    }

    func testAdvanceStepMovesForwardWhenValid() {
        let vm = loadedModel()
        vm.nativeLanguages = ["Japanese"]
        XCTAssertTrue(vm.advanceStep())
        XCTAssertEqual(vm.step, .target)
        XCTAssertTrue(vm.advancing, "moving forward sets advancing")
    }

    func testAdvanceStepReturnsFalseOnLastStep() {
        let vm = loadedModel()
        vm.step = .accents
        vm.targetAccents = ["US General"]
        XCTAssertFalse(vm.advanceStep(), "no step after accents → caller should save")
        XCTAssertEqual(vm.step, .accents)
        XCTAssertTrue(vm.isLastStep)
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
        vm.goBack()
        XCTAssertEqual(vm.step, .native)
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
