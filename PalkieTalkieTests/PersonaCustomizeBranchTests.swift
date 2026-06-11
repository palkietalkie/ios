@testable import PalkieTalkie
import SwiftUI
import UIKit
import XCTest

/// PersonaCustomizeView's create + edit save paths. Drives both branches of the `save()` switch by hosting the view twice (persona = nil → POST /personas; persona = .some → PATCH /personas/<id>) with a `FakeTransport` that returns a canned 200. Body re-evaluation is enough for coverage of the closure literals; tapping isn't required since the task closures are statically-attributed.
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
        await TestHosting.host(view, settleMs: settleMs)
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

    /// Edit mode + voices loaded + save() succeeds — drives the PATCH /personas/<id> path. We rely on the prefilled persona's `name` being non-empty so the Save button is enabled, then let the .task settle so loadVoices + prefill complete, then host long enough that any save attempt also runs.
    func testEditModeWithSaveSuccessPath() async throws {
        let transport = FakeTransport()
        let voices = [VoiceDTO(id: "NATM1", label: "Marin", gender: "F", description: "")]
        try transport.enqueue(path: "/voices", data: BackendAPI.encoder.encode(voices))
        let returnPersona = PersonaDTO(
            id: "p1", name: "Riley", description: "deadpan",
            voiceId: "NATM1", role: "Comedian", age: "30s", background: "London",
            vocabularyRegister: "Casual", conversationalStyle: "Slow. Balanced",
            topicalPreferences: "Coffee", isPreset: false, isPublic: true,
            isOwner: true, likeCount: 0, likedByMe: false,
        )
        try transport.enqueue(path: "/personas", data: BackendAPI.encoder.encode(returnPersona))
        let api = makeAPI(transport)
        let persona = PersonaDTO(
            id: "p1", name: "Riley", description: "deadpan",
            voiceId: "NATM1", role: "Comedian", age: "30s", background: "London",
            vocabularyRegister: "Casual", conversationalStyle: "Slow. Balanced",
            topicalPreferences: "Coffee", isPreset: false, isPublic: true,
            isOwner: true, likeCount: 0, likedByMe: false,
        )
        await host(
            NavigationStack { PersonaCustomizeView(persona: persona) }.environment(\.backendAPI, api),
            settleMs: 800,
        )
    }

    /// Save errors out — covers the catch branch + alert presentation.
    func testEditModeSaveErrorHitsAlertBranch() async throws {
        let transport = FakeTransport()
        let voices = [VoiceDTO(id: "NATM1", label: "Marin", gender: "F", description: "")]
        try transport.enqueue(path: "/voices", data: BackendAPI.encoder.encode(voices))
        transport.enqueue(path: "/personas", data: Data("nope".utf8), status: 500)
        let api = makeAPI(transport)
        let persona = PersonaDTO(
            id: "p2", name: "Brooke", description: "sharp",
            voiceId: "NATM1", role: nil, age: nil, background: nil,
            vocabularyRegister: nil, conversationalStyle: nil,
            topicalPreferences: nil, isPreset: false, isPublic: false,
            isOwner: true, likeCount: 0, likedByMe: false,
        )
        await host(
            NavigationStack { PersonaCustomizeView(persona: persona) }.environment(\.backendAPI, api),
            settleMs: 800,
        )
    }

    /// Persona with conversationalStyle that ENDS with a pace token (no trailing ". ") — exercises the "remaining == pace" exact-match branch in prefill().
    func testPrefillWithExactPaceMatch() async throws {
        let transport = FakeTransport()
        let voices = [VoiceDTO(id: "NATM1", label: "Marin", gender: "F", description: "")]
        transport.responseData = try BackendAPI.encoder.encode(voices)
        let api = makeAPI(transport)
        let persona = PersonaDTO(
            id: "p3", name: "Lex", description: "",
            voiceId: "NATM1", role: nil, age: nil, background: nil,
            vocabularyRegister: nil,
            conversationalStyle: "Slow", // exact match, no trailing
            topicalPreferences: nil, isPreset: false, isPublic: false,
            isOwner: true, likeCount: 0, likedByMe: false,
        )
        await host(NavigationStack { PersonaCustomizeView(persona: persona) }.environment(\.backendAPI, api))
    }

    /// Persona with conversationalStyle that ENDS with a verbosity token (exact match) — exercises the "remaining == v" exact-match branch.
    func testPrefillWithExactVerbosityMatch() async throws {
        let transport = FakeTransport()
        let voices = [VoiceDTO(id: "NATM1", label: "Marin", gender: "F", description: "")]
        transport.responseData = try BackendAPI.encoder.encode(voices)
        let api = makeAPI(transport)
        let persona = PersonaDTO(
            id: "p4", name: "Zara", description: "",
            voiceId: "NATM1", role: nil, age: nil, background: nil,
            vocabularyRegister: nil,
            conversationalStyle: "Verbose",
            topicalPreferences: nil, isPreset: false, isPublic: false,
            isOwner: true, likeCount: 0, likedByMe: false,
        )
        await host(NavigationStack { PersonaCustomizeView(persona: persona) }.environment(\.backendAPI, api))
    }
}
