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
