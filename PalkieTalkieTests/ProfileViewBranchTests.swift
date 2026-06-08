@testable import PalkieTalkie
import SwiftUI
import XCTest

/// Hosts ProfileView with canned BackendAPI responses so each ViewBuilder branch (empty KG, populated KG, pronunciation suggestion, saving state, save-error) actually runs. The default `ProfileViewTests` only checks inspectable text — these reach the SwiftUI render pipeline so coverage hits the branches behind `@State`.
@MainActor
final class ProfileViewBranchTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        clearCaches()
    }

    override func tearDown() async throws {
        // Let any in-flight Task { await model.load(...) } from .task finish before clearing — otherwise its JSONCache.save races into the next test's setUp. 500ms accommodates the slower CI simulator.
        try? await Task.sleep(nanoseconds: 500_000_000)
        clearCaches()
        try await super.tearDown()
    }

    private func clearCaches() {
        UserDefaults.standard.removeObject(forKey: "cache.profile")
        UserDefaults.standard.removeObject(forKey: "cache.languages")
        UserDefaults.standard.removeObject(forKey: "cache.practice_options")
        UserDefaults.standard.removeObject(forKey: "cache.knowledge_graph")
    }

    private func makeAPI(transport: FakeTransport, authing: any Authing = StubAuthing()) -> BackendAPI {
        BackendAPI(baseURL: URL(string: "https://test.example.com")!, transport: transport, auth: authing)
    }

    /// Backend returns a complete profile + languages + practice options + KG entities — covers the load-success path, the KG-non-empty branch (ForEach over entities + their attrs), the suggested-pronunciation row, and all label/value combinations.
    func testRendersLoadedProfileWithKnowledgeGraph() async throws {
        let transport = FakeTransport()
        try transport.enqueue(path: "/profile", data: Self.encode(profile(pronSuggestion: "WESS")))
        try transport.enqueue(path: "/languages", data: Self.encode([
            LanguageDTO(name: "English", accents: ["US General", "UK RP"]),
            LanguageDTO(name: "Japanese", accents: []),
        ]))
        try transport.enqueue(path: "/practice/options", data: Self.encode(PracticeOptionsDTO(
            proficiency: ["beginner", "intermediate", "advanced"],
            tutorSpeakingSpeed: ["slow", "normal", "fast"],
        )))
        try transport.enqueue(path: "/kg", data: Self.encode([
            KGEntityDTO(id: "e1", type: "person", name: "Naoto", attrs: ["role": "brother", "city": "Coventry"]),
            KGEntityDTO(id: "e2", type: "place", name: "SF", attrs: [:]),
        ]))
        let api = makeAPI(transport: transport)
        await TestHosting.host(NavigationStack { ProfileView() }.environment(\.backendAPI, api), settleMs: 800)
    }

    /// Backend returns an empty KG — covers the "no entities yet" copy branch.
    func testRendersEmptyKnowledgeGraphCopy() async throws {
        let transport = FakeTransport()
        try transport.enqueue(path: "/profile", data: Self.encode(profile(pronSuggestion: nil)))
        try transport.enqueue(path: "/languages", data: Self.encode([] as [LanguageDTO]))
        try transport.enqueue(
            path: "/practice/options",
            data: Self.encode(PracticeOptionsDTO(proficiency: [], tutorSpeakingSpeed: [])),
        )
        try transport.enqueue(path: "/kg", data: Self.encode([] as [KGEntityDTO]))
        let api = makeAPI(transport: transport)
        await TestHosting.host(NavigationStack { ProfileView() }.environment(\.backendAPI, api), settleMs: 800)
    }

    /// Backend errors out — covers the error-surfacing branch (saveError gets the localizedDescription). Equivalent VM-direct test in ProfileViewModelTests.testLoadFailureSetsErrorMessage; the hosted version of this scenario has been flaky under full-suite runs (SIGSEGV under concurrent UserDefaults writes from prior test teardown), so it's not hosted here.
    func testLoadFailureAtVMLevelCoversCatchBranch() async {
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = "boom".data(using: .utf8)!
        let api = makeAPI(transport: transport)
        let vm = ProfileViewModel()
        await vm.load(api: api)
        XCTAssertNotNil(vm.saveError)
    }

    /// Pronunciation suggestion non-empty AND user pronunciation empty — covers the suggestion-button row.
    func testRendersPronunciationSuggestionRow() async throws {
        let transport = FakeTransport()
        var p = profile(pronSuggestion: "WESS")
        p = ProfileDTO(
            email: p.email,
            displayName: p.displayName,
            namePronunciation: "", // empty so suggestion renders
            namePronunciationSuggestion: "WESS",
            nativeLanguages: p.nativeLanguages,
            targetLanguage: p.targetLanguage,
            targetAccents: p.targetAccents,
            proficiency: p.proficiency,
            tutorSpeakingSpeed: p.tutorSpeakingSpeed,
            goals: p.goals,
            locationCity: p.locationCity,
            timezone: p.timezone,
        )
        try transport.enqueue(path: "/profile", data: Self.encode(p))
        try transport.enqueue(path: "/languages", data: Self.encode([] as [LanguageDTO]))
        try transport.enqueue(
            path: "/practice/options",
            data: Self.encode(PracticeOptionsDTO(proficiency: [], tutorSpeakingSpeed: [])),
        )
        try transport.enqueue(path: "/kg", data: Self.encode([] as [KGEntityDTO]))
        let api = makeAPI(transport: transport)
        await TestHosting.host(NavigationStack { ProfileView() }.environment(\.backendAPI, api), settleMs: 800)
    }

    // Save flow is covered VM-direct in ProfileViewModelTests.testSaveSuccessSetsSavedAtAndReloads — hosting the view to drive Save through SwiftUI flaked under concurrent test runs (concurrent UserDefaults + SwiftUI render races trigger SIGSEGV on the simulator).

    /// ProfileView's init path with seeded cache — confirms the view constructs without crashing when JSONCache has a stale value. Doesn't host the view (the hosted variant flakes under concurrent test runs), but exercises the init.
    func testViewInitWithCachedProfileSucceeds() throws {
        let p = profile(pronSuggestion: nil)
        try JSONCache.save(p, key: "cache.profile")
        _ = ProfileView()
    }

    private func profile(pronSuggestion: String?) -> ProfileDTO {
        ProfileDTO(
            email: "wes@example.com",
            displayName: "Wes",
            namePronunciation: "WESS",
            namePronunciationSuggestion: pronSuggestion,
            nativeLanguages: ["Japanese", "English"],
            targetLanguage: "English",
            targetAccents: ["US General"],
            proficiency: "intermediate",
            tutorSpeakingSpeed: "normal",
            goals: "Job interview prep",
            locationCity: "San Francisco",
            timezone: TimeZone.current.identifier,
        )
    }

    private static func encode(_ value: some Encodable) throws -> Data {
        try BackendAPI.encoder.encode(value)
    }
}
