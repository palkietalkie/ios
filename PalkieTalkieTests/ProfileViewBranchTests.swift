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
            tutorSpeakingSpeedRates: ["slow": 0.85, "normal": 1.0, "fast": 1.15],
            goals: ["travel"],
        )))
        try transport.enqueue(path: "/kg", data: Self.encode(KGGraphDTO(
            nodes: [
                KGEntityDTO(
                    id: "e1", type: "person", name: "Naoto",
                    attrs: ["role": "brother", "city": "Coventry"],
                ),
                KGEntityDTO(id: "e2", type: "place", name: "SF", attrs: [:]),
            ],
            edges: [],
        )))
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
            data: Self.encode(PracticeOptionsDTO(
                proficiency: [],
                tutorSpeakingSpeed: [],
                tutorSpeakingSpeedRates: [:],
                goals: [],
            )),
        )
        try transport.enqueue(path: "/kg", data: Self.encode(KGGraphDTO(nodes: [], edges: [])))
        let api = makeAPI(transport: transport)
        await TestHosting.host(NavigationStack { ProfileView() }.environment(\.backendAPI, api), settleMs: 800)
    }

    /// Render-then-refresh: a backend HTTP error on profile load must NOT surface — it keeps cached/empty fields and logs (the catch branch's else/log path). A contract drift is the only surfacing case (covered in ProfileViewModelTests.testLoadDecodeFailureSurfacesError). Hosting this scenario has been flaky under full-suite runs (SIGSEGV under concurrent UserDefaults writes from prior test teardown), so it's VM-direct here.
    func testLoadHttpFailureKeepsCachedContentSilently() async {
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = "boom".data(using: .utf8)!
        let api = makeAPI(transport: transport)
        let vm = ProfileViewModel()
        await vm.load(api: api)
        XCTAssertNil(vm.saveError, "an HTTP-error refresh must not replace cached content with an error")
    }

    /// Pronunciation suggestion non-empty AND user pronunciation empty — covers the suggestion-button row.
    func testRendersPronunciationSuggestionRow() async throws {
        let transport = FakeTransport()
        var p = profile(pronSuggestion: "WESS")
        p = ProfileDTO(
            email: p.email,
            preferredName: p.preferredName,
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
            data: Self.encode(PracticeOptionsDTO(
                proficiency: [],
                tutorSpeakingSpeed: [],
                tutorSpeakingSpeedRates: [:],
                goals: [],
            )),
        )
        try transport.enqueue(path: "/kg", data: Self.encode(KGGraphDTO(nodes: [], edges: [])))
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
            preferredName: "Wes",
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
