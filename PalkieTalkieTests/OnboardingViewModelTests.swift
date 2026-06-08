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

    func testLoadFailureLeavesEmptyArray() async {
        let transport = FakeTransport()
        transport.responseStatus = 500
        let api = makeAPI(transport)
        let vm = OnboardingViewModel()
        await vm.load(api: api)
        XCTAssertEqual(vm.languages.count, 0)
        XCTAssertFalse(vm.loading)
    }

    func testSaveSuccessFlipsDidSaveSuccessfully() async throws {
        let transport = FakeTransport()
        let profile = ProfileDTO(
            email: nil,
            displayName: nil,
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
