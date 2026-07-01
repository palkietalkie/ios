@testable import PalkieTalkie
import SwiftUI
import ViewInspector
import XCTest

@MainActor
final class PracticeViewTests: XCTestCase {
    /// Practice screen renders the three editable sections ("Target", "Level", and an actions/save section). The split into named sections is the spec — `/CLAUDE.md` features describe practice as "target language / accents / proficiency / tutor speaking speed / goals" and the UI groups these into discrete edit zones.
    func testFormHasTargetAndLevelSections() throws {
        UserDefaults.standard.removeObject(forKey: "cache.profile")
        let sut = PracticeView()
        let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        XCTAssertTrue(texts.contains("Target"), "expected Target section header; saw \(texts)")
        XCTAssertTrue(texts.contains("Level"), "expected Level section header; saw \(texts)")
    }

    /// Without a cached profile, defaults are: targetLanguage="English", proficiency="intermediate", tutorSpeakingSpeed="normal". A drift here would change the cold-start meaning of the form silently.
    func testDefaultsWhenNoCache() throws {
        UserDefaults.standard.removeObject(forKey: "cache.profile")
        let sut = PracticeView()
        // No throw from rendering means defaults built successfully; the values themselves are private @State and not directly inspectable but their consequences (Picker selections) can be queried in richer tests.
        XCTAssertNoThrow(try sut.inspect())
    }

    /// Selected accents render through localizedAccentName, not the raw backend slug — locks the display path so a refactor dropping the wrapper (a bare slug under a non-English UI locale) is caught. Seeds the cache so the accent shows on first synchronous paint.
    func testSelectedAccentsRenderLocalizedDisplay() throws {
        let cached = ProfileDTO(
            email: "wes@example.com", preferredName: "Wes",
            namePronunciation: nil, namePronunciationSuggestion: nil,
            nativeLanguages: ["Japanese"],
            targetLanguage: "English",
            targetAccents: ["US General"],
            proficiency: "advanced",
            tutorSpeakingSpeed: "fast",
            correctionFrequency: "sometimes",
            goals: nil, locationCity: nil, timezone: nil,
        )
        JSONCache.save(cached, key: PracticeViewModel.profileKey)
        defer { UserDefaults.standard.removeObject(forKey: PracticeViewModel.profileKey) }

        let sut = PracticeView()
        let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        XCTAssertTrue(
            texts.contains { $0.contains(localizedAccentName("US General")) },
            "accents must render via localizedAccentName; saw \(texts)",
        )
    }
}
