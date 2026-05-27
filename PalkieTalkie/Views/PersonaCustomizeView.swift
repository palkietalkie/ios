import SwiftUI

private let vocabularyOptions: [String] = [
    "Casual",
    "Professional",
    "Slang-heavy",
    "Domain-specific"
]

private let conversationalStyleOptions: [String] = [
    "Fast and punchy",
    "Slow and deliberate",
    "Mixed pace",
    "Verbose",
    "Terse"
]

@MainActor
struct PersonaCustomizeView: View {
    let persona: PersonaDTO?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var personaDescription: String = ""
    @State private var voiceId: String = "NATM1"
    @State private var role: String = ""
    @State private var age: String = ""
    @State private var background: String = ""
    @State private var vocabularyChoice: String = ""
    @State private var vocabularyCustom: String = ""
    @State private var conversationalChoice: String = ""
    @State private var conversationalCustom: String = ""
    @State private var topicalPreferences: String = ""
    @State private var isPublic: Bool = false
    @State private var voices: [VoiceDTO] = []
    @State private var saving: Bool = false
    @State private var saveError: String?

    private var vocabularyResolved: String {
        let pieces = [vocabularyChoice, vocabularyCustom].filter { !$0.isEmpty }
        return pieces.joined(separator: ". ")
    }

    private var conversationalResolved: String {
        let pieces = [conversationalChoice, conversationalCustom].filter { !$0.isEmpty }
        return pieces.joined(separator: ". ")
    }

    var body: some View {
        Form {
            Section {
                TextField("e.g. Jimmy Carr", text: $name)
            } header: {
                Text("Name")
            }
            Section {
                TextField("One-liner about the character", text: $personaDescription, axis: .vertical)
                    .lineLimit(2 ... 4)
            } header: {
                Text("Description")
            }
            Section {
                if voices.isEmpty {
                    ProgressView()
                } else {
                    Picker("Voice", selection: $voiceId) {
                        ForEach(voices) { voice in
                            Text("\(voice.id) — \(voice.label)").tag(voice.id)
                        }
                    }
                }
            } header: {
                Text("Voice")
            }
            Section {
                TextField("e.g. A dry, deadpan British observational comedian.", text: $role, axis: .vertical)
                    .lineLimit(2 ... 4)
            } header: {
                Text("Role")
            } footer: {
                Text("Who they are. The basic identity the AI inhabits.")
            }
            Section {
                TextField("e.g. Late 20s, 40s, 70s", text: $age)
            } header: {
                Text("Age")
            } footer: {
                Text("Drives pacing and word choice indirectly. Free text.")
            }
            Section {
                TextField("e.g. Lives in SF, works at an early-stage startup.", text: $background, axis: .vertical)
                    .lineLimit(2 ... 4)
            } header: {
                Text("Background")
            } footer: {
                Text("Where they're from, what they do, what shapes how they see things.")
            }
            Section {
                Picker("Style", selection: $vocabularyChoice) {
                    Text("None").tag("")
                    ForEach(vocabularyOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                TextField("Or describe in your own words", text: $vocabularyCustom, axis: .vertical)
                    .lineLimit(1 ... 3)
            } header: {
                Text("Vocabulary")
            } footer: {
                Text("Pick a style, write your own, or both.")
            }
            Section {
                Picker("Pace", selection: $conversationalChoice) {
                    Text("None").tag("")
                    ForEach(conversationalStyleOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                TextField("Or describe in your own words", text: $conversationalCustom, axis: .vertical)
                    .lineLimit(1 ... 3)
            } header: {
                Text("Conversational style")
            } footer: {
                Text("Speed and turn-taking habits — pick a pace, write your own, or both.")
            }
            Section {
                TextField("e.g. Product design, hikes, coffee shops.", text: $topicalPreferences, axis: .vertical)
                    .lineLimit(1 ... 3)
            } header: {
                Text("Topics they bring up")
            } footer: {
                Text("What they ask about, what they steer toward.")
            }
            Section {
                Toggle("Share with community", isOn: $isPublic)
            } footer: {
                Text("Public personas appear in everyone's persona library. They can like and use yours.")
            }
            Section {
                Button(persona == nil ? "Create" : "Save", action: { Task { await save() } })
                    .disabled(name.isEmpty || saving)
            }
        }
        .navigationTitle(persona == nil ? "New persona" : "Edit persona")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: prefill)
        .task { await loadVoices() }
        .alert("Couldn't save", isPresented: .constant(saveError != nil)) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func prefill() {
        guard let persona else { return }
        name = persona.name
        personaDescription = persona.description
        voiceId = persona.voiceId
        role = persona.role ?? ""
        age = persona.age ?? ""
        background = persona.background ?? ""
        let vocab = persona.vocabularyRegister ?? ""
        if vocabularyOptions.contains(vocab) {
            vocabularyChoice = vocab
        } else {
            vocabularyCustom = vocab
        }
        let convo = persona.conversationalStyle ?? ""
        if conversationalStyleOptions.contains(convo) {
            conversationalChoice = convo
        } else {
            conversationalCustom = convo
        }
        topicalPreferences = persona.topicalPreferences ?? ""
        isPublic = persona.isPublic
    }

    private func loadVoices() async {
        do {
            voices = try await BackendAPI.shared.getVoices()
        } catch {
            // voices fetch failure isn't fatal — Save will surface a proper backend error if the id is invalid.
        }
    }

    private func save() async {
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
                    isPublic: isPublic
                )
                _ = try await BackendAPI.shared.updatePersona(id: persona.id, payload)
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
                    isPublic: isPublic
                )
                _ = try await BackendAPI.shared.createPersona(payload)
            }
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
