@testable import PalkieTalkie
import SwiftUI
import XCTest

@MainActor
final class PersonaPickerViewTests: XCTestCase {
    func testSortOptionRawValuesStayUnique() {
        let raws = PersonaPickerView.SortOption.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count, "a duplicate raw value would collapse two sort modes into one")
    }

    /// SortOption labels are the user-visible strings in the picker. Locking them so a refactor that renames "Most liked" → "Liked" silently shifts the UI.
    func testSortOptionLabelsMatchSpec() {
        XCTAssertEqual(PersonaPickerView.SortOption.recommended.label, "Recommended")
        XCTAssertEqual(PersonaPickerView.SortOption.popular.label, "Most liked")
        XCTAssertEqual(PersonaPickerView.SortOption.recent.label, "Recent")
    }

    /// All three sort options exist as cases. A drop would silently kill a sort branch — the toolbar Picker iterates `allCases` so a missing case = a missing entry users can't reach.
    func testSortOptionAllCasesHasExactlyThree() {
        XCTAssertEqual(PersonaPickerView.SortOption.allCases.count, 3)
    }

    /// `SortOption.id == rawValue` is required by Identifiable conformance — the picker iterates `allCases` and uses the id to build the menu. A drift would compile but break the picker's selection persistence.
    func testSortOptionIdEqualsRawValue() {
        for option in PersonaPickerView.SortOption.allCases {
            XCTAssertEqual(option.id, option.rawValue)
        }
    }

    /// Report is offered only on community personas (public, not a preset, not mine). Locks the moderation surface: a regression that made presets or your own personas reportable, or hid the button on real community content, would break App Store 1.2 compliance or annoy users.
    func testOnlyCommunityPersonasAreReportable() {
        func persona(isPreset: Bool, isPublic: Bool, isOwner: Bool) -> PersonaDTO {
            PersonaDTO(id: "x", name: "X", description: "", voiceId: "NATM1",
                       role: nil, age: nil, background: nil, vocabularyRegister: nil,
                       conversationalStyle: nil, topicalPreferences: nil,
                       isPreset: isPreset, isPublic: isPublic, isOwner: isOwner,
                       likeCount: 0, likedByMe: false)
        }
        XCTAssertTrue(PersonaPickerView.isReportable(persona(isPreset: false, isPublic: true, isOwner: false)))
        XCTAssertFalse(
            PersonaPickerView.isReportable(persona(isPreset: true, isPublic: true, isOwner: false)),
            "presets are first-party",
        )
        XCTAssertFalse(
            PersonaPickerView.isReportable(persona(isPreset: false, isPublic: true, isOwner: true)),
            "can't report your own",
        )
        XCTAssertFalse(
            PersonaPickerView.isReportable(persona(isPreset: false, isPublic: false, isOwner: false)),
            "private personas aren't shared content",
        )
    }

    /// Hosts the picker with one preset, one owner, and one community persona so all three badge branches (`buildBadge` → `buildChip`) actually render without crashing. The list also exercises the row + like-column builders end to end.
    func testHostsPopulatedListRendersAllBadgeBranches() async throws {
        let transport = FakeTransport()
        let personas = [
            PersonaDTO(id: "p1", name: "Riley", description: "deadpan",
                       voiceId: "NATM1", role: "Comedian", age: "30s",
                       background: nil, vocabularyRegister: nil,
                       conversationalStyle: nil, topicalPreferences: nil,
                       isPreset: true, isPublic: false, isOwner: false,
                       likeCount: 0, likedByMe: false),
            PersonaDTO(id: "p2", name: "Brooke", description: "sharp",
                       voiceId: "NATM2", role: nil, age: nil,
                       background: nil, vocabularyRegister: nil,
                       conversationalStyle: nil, topicalPreferences: nil,
                       isPreset: false, isPublic: false, isOwner: true,
                       likeCount: 5, likedByMe: true),
            PersonaDTO(id: "p3", name: "Tay", description: "friendly",
                       voiceId: "NATM3", role: nil, age: nil,
                       background: nil, vocabularyRegister: nil,
                       conversationalStyle: nil, topicalPreferences: nil,
                       isPreset: false, isPublic: true, isOwner: false,
                       likeCount: 12, likedByMe: false),
        ]
        transport.responseData = try BackendAPI.encoder.encode(personas)
        let api = try BackendAPI(
            baseURL: XCTUnwrap(URL(string: "https://test.example.com")),
            transport: transport,
            auth: StubAuthing(),
        )
        let session = SessionController(backend: api)
        await TestHosting.host(
            NavigationStack { PersonaPickerView() }
                .environment(\.backendAPI, api)
                .environment(session),
            settleMs: 700,
        )
        UserDefaults.standard.removeObject(forKey: "cache.personas")
    }
}
