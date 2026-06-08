import Foundation
import Observation

/// View-model for `PersonaCustomizeView`. Owns all editable state + the prefill / loadVoices / save business logic so each can be unit-tested without rendering SwiftUI. View stays a thin shell that binds to the model's properties.
@MainActor
@Observable
final class PersonaCustomizeViewModel {
    let persona: PersonaDTO?
    var name: String = ""
    var personaDescription: String = ""
    var voiceId: String = "NATM1"
    var role: String = ""
    var age: String = ""
    var background: String = ""
    var vocabularyChoice: String = ""
    var vocabularyCustom: String = ""
    var paceChoice: String = ""
    var verbosityChoice: String = ""
    var conversationalCustom: String = ""
    var topicalPreferences: String = ""
    var isPublic: Bool = false
    var voices: [VoiceDTO] = []
    var saving: Bool = false
    var saveError: String?
    /// First-appearance guard so prefill() doesn't re-fire every time the view re-appears (e.g. after popping back from a sub-navigation) and clobber the user's edits with the original persona values.
    var didPrefill: Bool = false
    /// Set after a successful save so the view can call `dismiss()`. View observes and fires .dismiss when this flips to true.
    var didSaveSuccessfully: Bool = false

    static let vocabularyOptions: [String] = ["Casual", "Professional", "Slang-heavy", "Domain-specific"]
    static let paceOptions: [String] = ["Very slow", "Slow", "Natural pace", "Fast", "Very fast"]
    static let verbosityOptions: [String] = ["Very terse", "Terse", "Balanced", "Verbose", "Very verbose"]

    init(persona: PersonaDTO?) {
        self.persona = persona
    }

    var vocabularyResolved: String {
        [vocabularyChoice, vocabularyCustom].filter { !$0.isEmpty }.joined(separator: ". ")
    }

    var conversationalResolved: String {
        [paceChoice, verbosityChoice, conversationalCustom].filter { !$0.isEmpty }.joined(separator: ". ")
    }

    /// Idempotent — guarded by `didPrefill`. Splits the persona's `conversationalStyle` field back into the (pace, verbosity, custom) tuple by matching prefixes.
    func prefill() {
        guard !didPrefill else { return }
        didPrefill = true
        guard let persona else { return }
        name = persona.name
        personaDescription = persona.description
        voiceId = persona.voiceId
        role = persona.role ?? ""
        age = persona.age ?? ""
        background = persona.background ?? ""
        let vocab = persona.vocabularyRegister ?? ""
        if Self.vocabularyOptions.contains(vocab) {
            vocabularyChoice = vocab
        } else {
            vocabularyCustom = vocab
        }
        var remaining = persona.conversationalStyle ?? ""
        for pace in Self.paceOptions {
            if remaining == pace {
                paceChoice = pace
                remaining = ""
                break
            }
            if remaining.hasPrefix(pace + ". ") {
                paceChoice = pace
                remaining = String(remaining.dropFirst(pace.count + 2))
                break
            }
        }
        for v in Self.verbosityOptions {
            if remaining == v {
                verbosityChoice = v
                remaining = ""
                break
            }
            if remaining.hasPrefix(v + ". ") {
                verbosityChoice = v
                remaining = String(remaining.dropFirst(v.count + 2))
                break
            }
        }
        conversationalCustom = remaining
        topicalPreferences = persona.topicalPreferences ?? ""
        isPublic = persona.isPublic
    }

    func loadVoices(api: BackendAPI) async {
        do {
            voices = try await api.getVoices()
        } catch {
            // voices fetch failure isn't fatal — Save will surface a proper backend error if the id is invalid.
        }
    }

    func save(api: BackendAPI) async {
        saving = true
        defer { saving = false }
        let vocab = vocabularyResolved
        let convo = conversationalResolved
        do {
            if let persona {
                let payload = PersonaUpdatePayload(
                    name: name,
                    description: personaDescription,
                    voiceId: voiceId,
                    role: role.isEmpty ? nil : role,
                    age: age.isEmpty ? nil : age,
                    background: background.isEmpty ? nil : background,
                    vocabularyRegister: vocab.isEmpty ? nil : vocab,
                    conversationalStyle: convo.isEmpty ? nil : convo,
                    topicalPreferences: topicalPreferences.isEmpty ? nil : topicalPreferences,
                    isPublic: isPublic,
                )
                _ = try await api.updatePersona(id: persona.id, payload)
            } else {
                let payload = PersonaCreatePayload(
                    name: name,
                    description: personaDescription,
                    voiceId: voiceId,
                    role: role.isEmpty ? nil : role,
                    age: age.isEmpty ? nil : age,
                    background: background.isEmpty ? nil : background,
                    vocabularyRegister: vocab.isEmpty ? nil : vocab,
                    conversationalStyle: convo.isEmpty ? nil : convo,
                    topicalPreferences: topicalPreferences.isEmpty ? nil : topicalPreferences,
                    isPublic: isPublic,
                )
                _ = try await api.createPersona(payload)
            }
            didSaveSuccessfully = true
        } catch {
            saveError = error.localizedDescription
        }
    }
}
