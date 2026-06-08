@testable import PalkieTalkie
import SwiftUI
import ViewInspector
import XCTest

@MainActor
final class PersonaCustomizeViewTests: XCTestCase {
    /// Create-mode (nil persona) body builds. The view's body has many @State + @Environment dependencies; a refactor that breaks construction would surface here.
    func testCreateModeBodyBuilds() throws {
        let sut = PersonaCustomizeView(persona: nil)
        XCTAssertNoThrow(try sut.inspect())
    }

    /// Edit-mode (existing persona) body builds. Same protection as create-mode plus exercises the prefill state path.
    func testEditModeBodyBuilds() throws {
        let existing = PersonaDTO(
            id: UUID().uuidString,
            name: "MyCoach",
            description: "",
            voiceId: "alloy",
            role: nil,
            age: nil,
            background: nil,
            vocabularyRegister: nil,
            conversationalStyle: nil,
            topicalPreferences: nil,
            isPreset: false,
            isPublic: false,
            isOwner: true,
            likeCount: 0,
            likedByMe: false,
        )
        let sut = PersonaCustomizeView(persona: existing)
        XCTAssertNoThrow(try sut.inspect())
    }
}
