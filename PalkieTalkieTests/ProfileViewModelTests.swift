@testable import PalkieTalkie
import XCTest

/// Direct unit tests for the ProfileViewModel — no SwiftUI render pipeline. Covers load / save / cache-init / clerkDefaultPreferredName fallback.
@MainActor
final class ProfileViewModelTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: ProfileViewModel.profileKey)
        UserDefaults.standard.removeObject(forKey: ProfileViewModel.languagesKey)
        UserDefaults.standard.removeObject(forKey: ProfileViewModel.practiceOptionsKey)
        UserDefaults.standard.removeObject(forKey: ProfileViewModel.kgKey)
    }

    override func tearDown() async throws {
        // Let in-flight Tasks complete before clearing UserDefaults — otherwise their JSONCache.save races into the next test's setUp. 500ms covers slower simulators.
        try? await Task.sleep(nanoseconds: 500_000_000)
        UserDefaults.standard.removeObject(forKey: ProfileViewModel.profileKey)
        UserDefaults.standard.removeObject(forKey: ProfileViewModel.languagesKey)
        UserDefaults.standard.removeObject(forKey: ProfileViewModel.practiceOptionsKey)
        UserDefaults.standard.removeObject(forKey: ProfileViewModel.kgKey)
        try await super.tearDown()
    }

    private func makeAPI(_ transport: FakeTransport) -> BackendAPI {
        BackendAPI(baseURL: URL(string: "https://test.example.com")!, transport: transport, auth: StubAuthing())
    }

    private static let sampleProfile = ProfileDTO(
        email: "wes@example.com",
        preferredName: "Wes",
        namePronunciation: "WESS",
        namePronunciationSuggestion: nil,
        nativeLanguages: ["Japanese"],
        targetLanguage: "English",
        targetAccents: ["US General"],
        proficiency: "intermediate",
        tutorSpeakingSpeed: "normal",
        goals: "interview prep",
        locationCity: "SF",
        timezone: "America/Los_Angeles",
    )

    func testClerkDefaultPreferredNameReturnsEmptyWithoutSignedInUser() {
        // No Clerk user in the test bundle → first guard returns "".
        let name = ProfileViewModel.clerkDefaultPreferredName()
        XCTAssertEqual(name, "")
    }

    func testInitWithNoCacheHasDefaults() {
        let vm = ProfileViewModel()
        XCTAssertEqual(vm.email, "")
        XCTAssertEqual(vm.targetLanguage, "English")
        XCTAssertEqual(vm.proficiency, "intermediate")
        XCTAssertFalse(vm.loaded)
    }

    func testInitWithCachedProfileSeedsState() throws {
        try JSONCache.save(Self.sampleProfile, key: ProfileViewModel.profileKey)
        let vm = ProfileViewModel()
        XCTAssertEqual(vm.email, "wes@example.com")
        XCTAssertEqual(vm.preferredName, "Wes")
        XCTAssertEqual(vm.namePronunciation, "WESS")
        XCTAssertTrue(vm.loaded)
    }

    func testAccentsForTargetLanguageReturnsMatch() {
        let vm = ProfileViewModel()
        vm.languages = [
            LanguageDTO(name: "English", accents: ["US", "UK"]),
            LanguageDTO(name: "Japanese", accents: []),
        ]
        vm.targetLanguage = "English"
        XCTAssertEqual(vm.accentsForTargetLanguage, ["US", "UK"])
        vm.targetLanguage = "Mandarin"
        XCTAssertEqual(vm.accentsForTargetLanguage, [])
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
        try transport.enqueue(
            path: "/kg",
            data: BackendAPI.encoder.encode(KGGraphDTO(
                nodes: [KGEntityDTO(id: "e1", type: "person", name: "Naoto", attrs: [:])],
                edges: [],
            )),
        )
        let api = makeAPI(transport)
        let vm = ProfileViewModel()
        await vm.load(api: api)
        XCTAssertEqual(vm.email, "wes@example.com")
        XCTAssertEqual(vm.preferredName, "Wes")
        XCTAssertEqual(vm.knowledgeGraph.count, 1)
        XCTAssertTrue(vm.loaded)
        XCTAssertNil(vm.saveError)
    }

    /// Regression: getKG() used to be `try?`, so a contract mismatch (backend `{nodes,edges}` vs an iOS bare-array decode) silently swallowed the error and showed every user an empty KG. Now a decode failure must surface in `kgError`. The bare `[]` here is exactly the pre-fix shape that no longer matches KGGraphDTO.
    func testKGDecodeFailureSurfacesError() async throws {
        let transport = FakeTransport()
        try transport.enqueue(path: "/profile", data: BackendAPI.encoder.encode(Self.sampleProfile))
        try transport.enqueue(path: "/languages", data: BackendAPI.encoder.encode([] as [LanguageDTO]))
        try transport.enqueue(
            path: "/practice/options",
            data: BackendAPI.encoder.encode(PracticeOptionsDTO(proficiency: [], tutorSpeakingSpeed: [])),
        )
        transport.enqueue(path: "/kg", data: Data("[]".utf8))
        let api = makeAPI(transport)
        let vm = ProfileViewModel()
        await vm.load(api: api)
        XCTAssertNotNil(vm.kgError, "a KG decode failure must surface, not silently show an empty graph")
    }

    func testLoadFailureSetsErrorMessage() async {
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = Data("boom".utf8)
        let api = makeAPI(transport)
        let vm = ProfileViewModel()
        await vm.load(api: api)
        XCTAssertNotNil(vm.saveError)
        XCTAssertFalse(vm.loaded)
    }

    func testSaveSuccessSetsSavedAtAndReloads() async throws {
        let transport = FakeTransport()
        try transport.enqueue(path: "/profile", data: BackendAPI.encoder.encode(Self.sampleProfile))
        try transport.enqueue(path: "/languages", data: BackendAPI.encoder.encode([] as [LanguageDTO]))
        try transport.enqueue(
            path: "/practice/options",
            data: BackendAPI.encoder.encode(PracticeOptionsDTO(proficiency: [], tutorSpeakingSpeed: [])),
        )
        try transport.enqueue(path: "/kg", data: BackendAPI.encoder.encode(KGGraphDTO(nodes: [], edges: [])))
        let api = makeAPI(transport)
        let vm = ProfileViewModel()
        vm.preferredName = "New Name"
        await vm.save(api: api)
        XCTAssertNotNil(vm.savedAt)
        XCTAssertNil(vm.saveError)
    }

    func testSaveFailureSetsErrorMessage() async {
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = Data("boom".utf8)
        let api = makeAPI(transport)
        let vm = ProfileViewModel()
        await vm.save(api: api)
        XCTAssertNotNil(vm.saveError)
        XCTAssertNil(vm.savedAt)
    }

    func testSaveSendsNilForEmptyOptionalFields() async throws {
        let transport = FakeTransport()
        try transport.enqueue(path: "/profile", data: BackendAPI.encoder.encode(Self.sampleProfile))
        try transport.enqueue(path: "/languages", data: BackendAPI.encoder.encode([] as [LanguageDTO]))
        try transport.enqueue(
            path: "/practice/options",
            data: BackendAPI.encoder.encode(PracticeOptionsDTO(proficiency: [], tutorSpeakingSpeed: [])),
        )
        try transport.enqueue(path: "/kg", data: BackendAPI.encoder.encode(KGGraphDTO(nodes: [], edges: [])))
        let api = makeAPI(transport)
        let vm = ProfileViewModel()
        // Leave preferredName / nativeLanguages / targetAccents / goals empty so they all serialize as nil.
        await vm.save(api: api)
        let patch = transport.requests.first(where: { $0.httpMethod == "PATCH" })
        let body = patch?.httpBody ?? Data()
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
        XCTAssertNil(json["display_name"])
        XCTAssertNil(json["native_languages"])
        XCTAssertNil(json["target_accents"])
        XCTAssertNil(json["goals"])
        // namePronunciation always sent (intentional — empty string is a real clear).
        XCTAssertNotNil(json["name_pronunciation"])
    }
}
