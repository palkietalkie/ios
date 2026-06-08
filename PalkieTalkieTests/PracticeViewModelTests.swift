@testable import PalkieTalkie
import XCTest

@MainActor
final class PracticeViewModelTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        clearCaches()
    }

    override func tearDown() async throws {
        clearCaches()
        try await super.tearDown()
    }

    private func clearCaches() {
        UserDefaults.standard.removeObject(forKey: PracticeViewModel.profileKey)
        UserDefaults.standard.removeObject(forKey: PracticeViewModel.languagesKey)
        UserDefaults.standard.removeObject(forKey: PracticeViewModel.practiceOptionsKey)
    }

    private func makeAPI(_ transport: FakeTransport) -> BackendAPI {
        BackendAPI(baseURL: URL(string: "https://test.example.com")!, transport: transport, auth: StubAuthing())
    }

    private static let sampleProfile = ProfileDTO(
        email: "wes@example.com", displayName: "Wes",
        namePronunciation: nil, namePronunciationSuggestion: nil,
        nativeLanguages: ["Japanese"],
        targetLanguage: "English",
        targetAccents: ["US General"],
        proficiency: "advanced",
        tutorSpeakingSpeed: "fast",
        goals: "freeform", locationCity: nil, timezone: nil,
    )

    func testInitWithNoCacheHasDefaults() {
        let vm = PracticeViewModel()
        XCTAssertEqual(vm.targetLanguage, "English")
        XCTAssertEqual(vm.proficiency, "intermediate")
        XCTAssertFalse(vm.loaded)
    }

    func testInitWithCachedProfileSeedsState() throws {
        try JSONCache.save(Self.sampleProfile, key: PracticeViewModel.profileKey)
        let vm = PracticeViewModel()
        XCTAssertEqual(vm.targetLanguage, "English")
        XCTAssertEqual(vm.targetAccents, ["US General"])
        XCTAssertEqual(vm.proficiency, "advanced")
        XCTAssertEqual(vm.tutorSpeakingSpeed, "fast")
        XCTAssertEqual(vm.goals, "freeform")
        XCTAssertTrue(vm.loaded)
    }

    func testDisplaySnakeCaseToCapitalized() {
        XCTAssertEqual(PracticeViewModel.display("very_slow"), "Very slow")
        XCTAssertEqual(PracticeViewModel.display("normal"), "Normal")
        XCTAssertEqual(PracticeViewModel.display(""), "")
    }

    func testAccentsForTargetLanguageReturnsMatch() {
        let vm = PracticeViewModel()
        vm.languages = [LanguageDTO(name: "English", accents: ["US", "UK"])]
        vm.targetLanguage = "English"
        XCTAssertEqual(vm.accentsForTargetLanguage, ["US", "UK"])
    }

    func testFilterAccentsRemovesUnsupported() {
        let vm = PracticeViewModel()
        vm.languages = [
            LanguageDTO(name: "Japanese", accents: ["Tokyo"]),
            LanguageDTO(name: "English", accents: ["US"]),
        ]
        vm.targetAccents = ["US", "Tokyo"]
        vm.filterAccentsForTargetLanguage("Japanese")
        XCTAssertEqual(vm.targetAccents, ["Tokyo"], "US dropped (not in Japanese accents)")
    }

    func testFilterAccentsUnknownLanguageIsNoOp() {
        let vm = PracticeViewModel()
        vm.languages = [LanguageDTO(name: "English", accents: ["US"])]
        vm.targetAccents = ["US"]
        vm.filterAccentsForTargetLanguage("Mandarin")
        XCTAssertEqual(vm.targetAccents, ["US"], "unknown language → no filter applied")
    }

    func testLoadSuccessPopulatesState() async throws {
        let transport = FakeTransport()
        try transport.enqueue(path: "/profile", data: BackendAPI.encoder.encode(Self.sampleProfile))
        try transport.enqueue(
            path: "/languages",
            data: BackendAPI.encoder.encode([LanguageDTO(name: "English", accents: ["US"])]),
        )
        try transport.enqueue(
            path: "/practice/options",
            data: BackendAPI.encoder.encode(PracticeOptionsDTO(
                proficiency: ["beginner"],
                tutorSpeakingSpeed: ["normal"],
            )),
        )
        let api = makeAPI(transport)
        let vm = PracticeViewModel()
        await vm.load(api: api)
        XCTAssertEqual(vm.targetLanguage, "English")
        XCTAssertEqual(vm.proficiency, "advanced")
        XCTAssertTrue(vm.loaded)
        XCTAssertNil(vm.saveError)
    }

    func testLoadFailureSetsErrorMessage() async {
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = Data("boom".utf8)
        let api = makeAPI(transport)
        let vm = PracticeViewModel()
        await vm.load(api: api)
        XCTAssertNotNil(vm.saveError)
    }

    func testSaveSuccessSetsSavedAtAndReloads() async throws {
        let transport = FakeTransport()
        try transport.enqueue(path: "/profile", data: BackendAPI.encoder.encode(Self.sampleProfile))
        try transport.enqueue(path: "/languages", data: BackendAPI.encoder.encode([] as [LanguageDTO]))
        try transport.enqueue(
            path: "/practice/options",
            data: BackendAPI.encoder.encode(PracticeOptionsDTO(proficiency: [], tutorSpeakingSpeed: [])),
        )
        let api = makeAPI(transport)
        let vm = PracticeViewModel()
        vm.targetLanguage = "English"
        await vm.save(api: api)
        XCTAssertNotNil(vm.savedAt)
        XCTAssertNil(vm.saveError)
    }

    func testSaveFailureSetsErrorMessage() async {
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = Data("boom".utf8)
        let api = makeAPI(transport)
        let vm = PracticeViewModel()
        await vm.save(api: api)
        XCTAssertNotNil(vm.saveError)
        XCTAssertNil(vm.savedAt)
    }
}
