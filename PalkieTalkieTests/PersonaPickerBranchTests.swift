@testable import PalkieTalkie
import SwiftUI
import XCTest

/// Hosts PersonaPickerView with canned BackendAPI responses so each ViewBuilder branch evaluates (empty list ContentUnavailable, populated list with rows, like button states).
@MainActor
final class PersonaPickerBranchTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "cache.personas")
        super.tearDown()
    }

    private func makeAPI(_ transport: FakeTransport) -> BackendAPI {
        BackendAPI(baseURL: URL(string: "https://test.example.com")!, transport: transport, auth: StubAuthing())
    }

    private func makeSessionController(_ api: BackendAPI) -> SessionController {
        SessionController(backend: api)
    }

    func testRendersEmptyListContentUnavailable() async throws {
        let transport = FakeTransport()
        transport.responseData = try BackendAPI.encoder.encode([] as [PersonaDTO])
        let api = makeAPI(transport)
        let session = makeSessionController(api)
        await TestHosting.host(
            NavigationStack { PersonaPickerView() }
                .environment(\.backendAPI, api)
                .environment(session),
            settleMs: 600,
        )
    }

    func testRendersPopulatedListWithMixOfPresetAndCustom() async throws {
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
                       isPreset: false, isPublic: true, isOwner: true,
                       likeCount: 5, likedByMe: true),
            PersonaDTO(id: "p3", name: "Tay", description: "friendly",
                       voiceId: "NATM3", role: nil, age: nil,
                       background: nil, vocabularyRegister: nil,
                       conversationalStyle: nil, topicalPreferences: nil,
                       isPreset: false, isPublic: true, isOwner: false,
                       likeCount: 12, likedByMe: false),
        ]
        transport.responseData = try BackendAPI.encoder.encode(personas)
        let api = makeAPI(transport)
        let session = makeSessionController(api)
        await TestHosting.host(
            NavigationStack { PersonaPickerView() }
                .environment(\.backendAPI, api)
                .environment(session),
            settleMs: 700,
        )
    }

    func testRendersLoadErrorAsAlert() async {
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = Data("nope".utf8)
        let api = makeAPI(transport)
        let session = makeSessionController(api)
        await TestHosting.host(
            NavigationStack { PersonaPickerView() }
                .environment(\.backendAPI, api)
                .environment(session),
            settleMs: 600,
        )
    }
}
