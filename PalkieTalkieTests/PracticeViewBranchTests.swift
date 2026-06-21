@testable import PalkieTalkie
import SwiftUI
import XCTest

/// Hosts PracticeView with canned BackendAPI responses so the loaded-data branches actually evaluate (Picker over languages, accents NavigationLink label with selected accents, save section enabled, saveError display).
@MainActor
final class PracticeViewBranchTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        clearCaches()
    }

    override func tearDown() async throws {
        // Let in-flight Task { await model.load(...) } from .task finish before clearing — otherwise its JSONCache.save races into the next test's setUp. 500ms accommodates the slower CI simulator.
        try? await Task.sleep(nanoseconds: 500_000_000)
        clearCaches()
        try await super.tearDown()
    }

    private func clearCaches() {
        UserDefaults.standard.removeObject(forKey: "cache.profile")
        UserDefaults.standard.removeObject(forKey: "cache.languages")
        UserDefaults.standard.removeObject(forKey: "cache.practice_options")
    }

    private func makeAPI(_ transport: FakeTransport) -> BackendAPI {
        BackendAPI(baseURL: URL(string: "https://test.example.com")!, transport: transport, auth: StubAuthing())
    }

    func testRendersWithLoadedProfileAndLanguages() async throws {
        let transport = FakeTransport()
        try transport.enqueue(path: "/profile", data: Self.encode(Self.profile))
        try transport.enqueue(path: "/languages", data: Self.encode([
            LanguageDTO(name: "English", accents: ["US General", "UK RP", "Australian"]),
            LanguageDTO(name: "Japanese", accents: []),
        ]))
        try transport.enqueue(path: "/practice/options", data: Self.encode(PracticeOptionsDTO(
            proficiency: ["beginner", "lower_intermediate", "intermediate", "upper_intermediate", "advanced"],
            tutorSpeakingSpeed: ["very_slow", "slow", "normal", "fast", "very_fast"],
            goals: ["everyday_conversation", "travel", "dating_relationships"],
        )))
        let api = makeAPI(transport)
        await TestHosting.host(NavigationStack { PracticeView() }.environment(\.backendAPI, api), settleMs: 800)
    }

    // Load-failure VM-direct moved to PracticeViewModelTests.testLoadFailureSetsErrorMessage (same coverage, but the hosted-view tests in this class kept perturbing the simulator's state and the VM-direct test SIGSEGV'd unpredictably in the same process).

    func testRendersWithEmptyAccentsAndChooseLabel() async throws {
        let transport = FakeTransport()
        var p = Self.profile
        p = ProfileDTO(
            email: p.email, preferredName: p.preferredName, namePronunciation: p.namePronunciation,
            namePronunciationSuggestion: p.namePronunciationSuggestion,
            nativeLanguages: p.nativeLanguages,
            targetLanguage: p.targetLanguage,
            targetAccents: [], // empty → "Choose…" branch
            proficiency: p.proficiency,
            tutorSpeakingSpeed: p.tutorSpeakingSpeed,
            goals: p.goals,
            locationCity: p.locationCity,
            timezone: p.timezone,
        )
        try transport.enqueue(path: "/profile", data: Self.encode(p))
        try transport.enqueue(path: "/languages", data: Self.encode([
            LanguageDTO(name: "English", accents: ["US General"]),
        ]))
        try transport.enqueue(
            path: "/practice/options",
            data: Self.encode(PracticeOptionsDTO(
                proficiency: ["intermediate"],
                tutorSpeakingSpeed: ["normal"],
                goals: [],
            )),
        )
        let api = makeAPI(transport)
        await TestHosting.host(NavigationStack { PracticeView() }.environment(\.backendAPI, api), settleMs: 800)
    }

    private static let profile = ProfileDTO(
        email: "wes@example.com",
        preferredName: "Wes",
        namePronunciation: "WESS",
        namePronunciationSuggestion: nil,
        nativeLanguages: ["Japanese"],
        targetLanguage: "English",
        targetAccents: ["US General"],
        proficiency: "intermediate",
        tutorSpeakingSpeed: "normal",
        goals: "Job interview prep",
        locationCity: "San Francisco",
        timezone: TimeZone.current.identifier,
    )

    private static func encode(_ value: some Encodable) throws -> Data {
        try BackendAPI.encoder.encode(value)
    }
}
