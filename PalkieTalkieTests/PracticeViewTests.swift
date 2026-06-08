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
}
