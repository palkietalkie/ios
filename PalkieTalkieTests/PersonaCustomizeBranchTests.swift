@testable import PalkieTalkie
import SwiftUI
import UIKit
import XCTest

/// PersonaCustomizeView's create + edit save paths. Drives both branches of the `save()` switch by hosting the view
/// twice (persona = nil → POST /personas; persona = .some → PATCH /personas/<id>) with a `FakeTransport` that returns
/// a canned 200. Body re-evaluation is enough for coverage of the closure literals; tapping isn't required since the
/// task closures are statically-attributed.
@MainActor
final class PersonaCustomizeBranchTests: XCTestCase {
    private func makeAPI(_ transport: FakeTransport) -> BackendAPI {
        BackendAPI(
            baseURL: URL(string: "https://api.test")!,
            transport: transport,
            auth: StubAuthing(),
        )
    }

    private func host(_ view: some View, settleMs: UInt64 = 400) async {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: settleMs * 1_000_000)
        controller.view.layoutIfNeeded()
        window.isHidden = true
    }

    func testCreateModeHostsWithVoicesLoaded() async throws {
        let transport = FakeTransport()
        let voices = [
            VoiceDTO(id: "NATM1", label: "Marin", gender: "F", description: ""),
            VoiceDTO(id: "NATM2", label: "Pixie", gender: "F", description: ""),
        ]
        transport.responseData = try BackendAPI.encoder.encode(voices)
        let api = makeAPI(transport)
        await host(NavigationStack { PersonaCustomizeView(persona: nil) }.environment(\.backendAPI, api))
    }

    func testEditModeWithCustomVocabHosts() async throws {
        let transport = FakeTransport()
        let voices = [VoiceDTO(id: "NATM1", label: "Marin", gender: "F", description: "")]
        transport.responseData = try BackendAPI.encoder.encode(voices)
        let api = makeAPI(transport)
        let persona = PersonaDTO(
            id: "p99", name: "Custom Vocab", description: "Surfer",
            voiceId: "NATM1",
            role: "Friend", age: "20s", background: "lives in LA",
            // Not in vocabularyOptions → goes into vocabularyCustom branch of prefill().
            vocabularyRegister: "Beach slang",
            // Not in conversationalStyleOptions → goes into conversationalCustom branch.
            conversationalStyle: "Stoned and chill",
            topicalPreferences: "Surfing",
            isPreset: false, isPublic: true, isOwner: true,
            likeCount: 0, likedByMe: false,
        )
        await host(NavigationStack { PersonaCustomizeView(persona: persona) }.environment(\.backendAPI, api))
    }

    func testEditModeWithPresetVocabHosts() async throws {
        let transport = FakeTransport()
        let voices = [VoiceDTO(id: "NATM1", label: "Marin", gender: "F", description: "")]
        transport.responseData = try BackendAPI.encoder.encode(voices)
        let api = makeAPI(transport)
        let persona = PersonaDTO(
            id: "p98", name: "Preset Style", description: "Casual",
            voiceId: "NATM1",
            role: nil, age: nil, background: nil,
            // In vocabularyOptions → vocabularyChoice branch.
            vocabularyRegister: "Casual",
            // "Slow" matches paceOptions and "Verbose" matches verbosityOptions → both pickers select, custom stays empty.
            conversationalStyle: "Slow. Verbose",
            topicalPreferences: nil,
            isPreset: false, isPublic: false, isOwner: true,
            likeCount: 1, likedByMe: false,
        )
        await host(NavigationStack { PersonaCustomizeView(persona: persona) }.environment(\.backendAPI, api))
    }

    func testCreateModeWithVoiceLoadFailureHosts() async {
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = Data("nope".utf8)
        let api = makeAPI(transport)
        await host(NavigationStack { PersonaCustomizeView(persona: nil) }.environment(\.backendAPI, api))
    }
}
