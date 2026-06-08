@testable import PalkieTalkie
import XCTest

/// Tests the VM directly — no SwiftUI render pipeline. Covers prefill / loadVoices / save success / save failure / vocabulary + conversational resolution helpers.
@MainActor
final class PersonaCustomizeViewModelTests: XCTestCase {
    private func makeAPI(_ transport: FakeTransport) -> BackendAPI {
        BackendAPI(baseURL: URL(string: "https://test.example.com")!, transport: transport, auth: StubAuthing())
    }

    private func samplePersona(
        vocab: String? = nil,
        conv: String? = nil,
        topics: String? = nil,
        isPublic: Bool = false,
    ) -> PersonaDTO {
        PersonaDTO(
            id: "p1", name: "Riley", description: "deadpan",
            voiceId: "NATM1", role: "Comedian", age: "30s",
            background: "London",
            vocabularyRegister: vocab,
            conversationalStyle: conv,
            topicalPreferences: topics,
            isPreset: false, isPublic: isPublic, isOwner: true,
            likeCount: 0, likedByMe: false,
        )
    }

    func testInitWithNilPersonaHasDefaults() {
        let vm = PersonaCustomizeViewModel(persona: nil)
        XCTAssertNil(vm.persona)
        XCTAssertEqual(vm.name, "")
        XCTAssertEqual(vm.voiceId, "NATM1")
        XCTAssertFalse(vm.didPrefill)
        XCTAssertFalse(vm.didSaveSuccessfully)
    }

    func testPrefillIsIdempotentByDidPrefillGuard() {
        let vm = PersonaCustomizeViewModel(persona: samplePersona())
        vm.prefill()
        XCTAssertTrue(vm.didPrefill)
        XCTAssertEqual(vm.name, "Riley")
        vm.name = "Edited"
        vm.prefill() // should be a no-op
        XCTAssertEqual(vm.name, "Edited", "second prefill must not clobber user edits")
    }

    func testPrefillWithNilPersonaIsNoOp() {
        let vm = PersonaCustomizeViewModel(persona: nil)
        vm.prefill()
        XCTAssertTrue(vm.didPrefill)
        XCTAssertEqual(vm.name, "")
    }

    func testPrefillVocabularyChoiceWhenInPresetSet() {
        let vm = PersonaCustomizeViewModel(persona: samplePersona(vocab: "Casual"))
        vm.prefill()
        XCTAssertEqual(vm.vocabularyChoice, "Casual")
        XCTAssertEqual(vm.vocabularyCustom, "")
    }

    func testPrefillVocabularyCustomWhenNotInPresetSet() {
        let vm = PersonaCustomizeViewModel(persona: samplePersona(vocab: "Beach slang"))
        vm.prefill()
        XCTAssertEqual(vm.vocabularyChoice, "")
        XCTAssertEqual(vm.vocabularyCustom, "Beach slang")
    }

    func testPrefillSplitsPaceVerbosityAndCustomFromConversationalStyle() {
        let vm = PersonaCustomizeViewModel(persona: samplePersona(conv: "Slow. Verbose. ends in colloquialisms"))
        vm.prefill()
        XCTAssertEqual(vm.paceChoice, "Slow")
        XCTAssertEqual(vm.verbosityChoice, "Verbose")
        XCTAssertEqual(vm.conversationalCustom, "ends in colloquialisms")
    }

    func testPrefillExactPaceMatchOnly() {
        let vm = PersonaCustomizeViewModel(persona: samplePersona(conv: "Slow"))
        vm.prefill()
        XCTAssertEqual(vm.paceChoice, "Slow")
        XCTAssertEqual(vm.verbosityChoice, "")
        XCTAssertEqual(vm.conversationalCustom, "")
    }

    func testPrefillExactVerbosityMatchOnly() {
        let vm = PersonaCustomizeViewModel(persona: samplePersona(conv: "Verbose"))
        vm.prefill()
        XCTAssertEqual(vm.verbosityChoice, "Verbose")
        XCTAssertEqual(vm.conversationalCustom, "")
    }

    func testVocabularyResolvedJoinsChoiceAndCustom() {
        let vm = PersonaCustomizeViewModel(persona: nil)
        vm.vocabularyChoice = "Casual"
        vm.vocabularyCustom = "with surfer flavor"
        XCTAssertEqual(vm.vocabularyResolved, "Casual. with surfer flavor")
    }

    func testVocabularyResolvedIgnoresEmpty() {
        let vm = PersonaCustomizeViewModel(persona: nil)
        vm.vocabularyChoice = "Casual"
        vm.vocabularyCustom = ""
        XCTAssertEqual(vm.vocabularyResolved, "Casual")
    }

    func testConversationalResolvedJoinsAllThree() {
        let vm = PersonaCustomizeViewModel(persona: nil)
        vm.paceChoice = "Slow"
        vm.verbosityChoice = "Terse"
        vm.conversationalCustom = "no hedging"
        XCTAssertEqual(vm.conversationalResolved, "Slow. Terse. no hedging")
    }

    func testLoadVoicesSuccessPopulatesArray() async throws {
        let transport = FakeTransport()
        let voices = [
            VoiceDTO(id: "NATM1", label: "Marin", gender: "F", description: ""),
            VoiceDTO(id: "NATM2", label: "Pixie", gender: "F", description: ""),
        ]
        transport.responseData = try BackendAPI.encoder.encode(voices)
        let api = makeAPI(transport)
        let vm = PersonaCustomizeViewModel(persona: nil)
        await vm.loadVoices(api: api)
        XCTAssertEqual(vm.voices.count, 2)
    }

    func testLoadVoicesErrorSilentlyKeepsEmpty() async {
        let transport = FakeTransport()
        transport.responseStatus = 500
        let api = makeAPI(transport)
        let vm = PersonaCustomizeViewModel(persona: nil)
        await vm.loadVoices(api: api)
        XCTAssertEqual(vm.voices.count, 0)
    }

    func testSaveCreateSuccessFlipsDidSaveSuccessfully() async throws {
        let transport = FakeTransport()
        let returned = samplePersona()
        transport.responseData = try BackendAPI.encoder.encode(returned)
        let api = makeAPI(transport)
        let vm = PersonaCustomizeViewModel(persona: nil)
        vm.name = "New Persona"
        await vm.save(api: api)
        XCTAssertTrue(vm.didSaveSuccessfully)
        XCTAssertNil(vm.saveError)
    }

    func testSaveEditSuccessFlipsDidSaveSuccessfully() async throws {
        let transport = FakeTransport()
        let returned = samplePersona()
        transport.responseData = try BackendAPI.encoder.encode(returned)
        let api = makeAPI(transport)
        let vm = PersonaCustomizeViewModel(persona: returned)
        vm.prefill()
        await vm.save(api: api)
        XCTAssertTrue(vm.didSaveSuccessfully)
        XCTAssertNil(vm.saveError)
    }

    func testSaveCreateErrorSetsSaveErrorMessage() async {
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = Data("nope".utf8)
        let api = makeAPI(transport)
        let vm = PersonaCustomizeViewModel(persona: nil)
        vm.name = "Doomed"
        await vm.save(api: api)
        XCTAssertFalse(vm.didSaveSuccessfully)
        XCTAssertNotNil(vm.saveError)
    }

    func testSaveEditErrorSetsSaveErrorMessage() async {
        let transport = FakeTransport()
        transport.responseStatus = 500
        transport.responseData = Data("nope".utf8)
        let api = makeAPI(transport)
        let vm = PersonaCustomizeViewModel(persona: samplePersona())
        vm.prefill()
        await vm.save(api: api)
        XCTAssertFalse(vm.didSaveSuccessfully)
        XCTAssertNotNil(vm.saveError)
    }

    func testSaveSendsNilForEmptyOptionalFields() async throws {
        let transport = FakeTransport()
        let returned = samplePersona()
        transport.responseData = try BackendAPI.encoder.encode(returned)
        let api = makeAPI(transport)
        let vm = PersonaCustomizeViewModel(persona: nil)
        vm.name = "Min"
        // role, age, background, topical, vocab/convo resolved all empty → payload sends nil.
        await vm.save(api: api)
        XCTAssertTrue(vm.didSaveSuccessfully)
        // Inspect the last request body to confirm nil-instead-of-empty-string for these fields.
        let bodyData = transport.lastRequest?.httpBody ?? Data()
        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] ?? [:]
        XCTAssertNil(json["role"])
        XCTAssertNil(json["age"])
        XCTAssertNil(json["background"])
        XCTAssertNil(json["topical_preferences"])
        XCTAssertNil(json["vocabulary_register"])
        XCTAssertNil(json["conversational_style"])
    }
}
