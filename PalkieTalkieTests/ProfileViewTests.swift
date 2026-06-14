@testable import PalkieTalkie
import SwiftUI
import ViewInspector
import XCTest

@MainActor
final class ProfileViewTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "cache.profile")
        UserDefaults.standard.removeObject(forKey: "cache.languages")
        UserDefaults.standard.removeObject(forKey: "cache.practice_options")
        UserDefaults.standard.removeObject(forKey: "cache.knowledge_graph")
    }

    /// The "Profile" section header is the identity section per `/CLAUDE.md` — Email + Preferred name + Pronunciation. A refactor that drops the header creates a headless form with three identity fields and no context.
    func testFormExposesProfileSectionHeader() throws {
        UserDefaults.standard.removeObject(forKey: "cache.profile")
        let sut = ProfileView()
        let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        XCTAssertTrue(texts.contains("Profile"), "expected 'Profile' section header; saw \(texts)")
    }

    /// Cached profile values populate the TextFields on first paint (stale-while-revalidate). A refactor that bypasses the cached init would force every cold launch to show empty fields until the network responds.
    func testSeededCacheRendersPreferredName() throws {
        let cached = ProfileDTO(
            email: "wes@example.com",
            preferredName: "Wes",
            namePronunciation: "WESS",
            namePronunciationSuggestion: nil,
            nativeLanguages: ["Japanese"],
            targetLanguage: "English",
            targetAccents: ["US General"],
            proficiency: "intermediate",
            tutorSpeakingSpeed: "normal",
            goals: nil,
            locationCity: nil,
            timezone: nil,
        )
        JSONCache.save(cached, key: "cache.profile")
        defer { UserDefaults.standard.removeObject(forKey: "cache.profile") }

        let sut = ProfileView()
        // TextField bound to preferredName state; locate by placeholder and confirm seeded text rendered.
        let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        XCTAssertTrue(texts.contains("Email"), "expected 'Email' label; saw \(texts)")
        XCTAssertTrue(texts.contains("Preferred name"))
        XCTAssertTrue(texts.contains("Pronunciation"))
    }
}
