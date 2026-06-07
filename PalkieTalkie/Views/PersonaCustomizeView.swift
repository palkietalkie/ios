import SwiftUI

private let vocabularyOptions: [String] = [
    "Casual",
    "Professional",
    "Slang-heavy",
    "Domain-specific",
]

private let paceOptions: [String] = [
    "Very slow",
    "Slow",
    "Natural pace",
    "Fast",
    "Very fast",
]

private let verbosityOptions: [String] = [
    "Very terse",
    "Terse",
    "Balanced",
    "Verbose",
    "Very verbose",
]

@MainActor
struct PersonaCustomizeView: View {
    let persona: PersonaDTO?
    @Environment(\.backendAPI) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var personaDescription: String = ""
    @State private var voiceId: String = "NATM1"
    @State private var role: String = ""
    @State private var age: String = ""
    @State private var background: String = ""
    @State private var vocabularyChoice: String = ""
    @State private var vocabularyCustom: String = ""
    @State private var paceChoice: String = ""
    @State private var verbosityChoice: String = ""
    @State private var conversationalCustom: String = ""
    @State private var topicalPreferences: String = ""
    @State private var isPublic: Bool = false
    @State private var voices: [VoiceDTO] = []
    @State private var preview = VoicePreviewPlayer()
    @State private var saving: Bool = false
    @State private var saveError: String?
    /// First-appearance guard so prefill() doesn't re-fire every time the view re-appears (e.g. after popping back from a sub-navigation) and clobber the user's edits with the original persona values.
    @State private var didPrefill: Bool = false

    @ViewBuilder
    private func voiceRow(_ voice: VoiceDTO) -> some View {
        let isSelected = voiceId == voice.id
        let hasPreview = VoicePreviewPlayer.hasPreview(voice.id)
        let isPlaying = preview.nowPlaying == voice.id
        HStack {
            Button {
                voiceId = voice.id
            } label: {
                HStack {
                    Text(voice.label)
                    Spacer(minLength: 8)
                    if isSelected {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if hasPreview {
                Button {
                    if isPlaying {
                        preview.stop()
                    } else {
                        preview.play(voiceId: voice.id)
                    }
                } label: {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isPlaying ? "Stop preview" : "Play preview")
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Preview unavailable")
            }
        }
    }

    private var vocabularyResolved: String {
        let pieces = [vocabularyChoice, vocabularyCustom].filter { !$0.isEmpty }
        return pieces.joined(separator: ". ")
    }

    private var conversationalResolved: String {
        let pieces = [paceChoice, verbosityChoice, conversationalCustom].filter { !$0.isEmpty }
        return pieces.joined(separator: ". ")
    }

    var body: some View {
        Form {
            Section {
                TextField("e.g. Riley", text: $name)
            } header: {
                Text("Name")
            } footer: {
                Text("Shown in your persona library and used as the character's name in conversation.")
            }
            Section {
                TextField("One-liner shown in your library", text: $personaDescription, axis: .vertical)
                    .lineLimit(2 ... 4)
            } header: {
                Text("Tagline")
            } footer: {
                Text("Library preview text. Not sent to the AI.")
            }
            Section {
                if voices.isEmpty {
                    ProgressView()
                } else {
                    ForEach(voices) { voice in
                        voiceRow(voice)
                    }
                }
            } header: {
                Text("Voice")
            } footer: {
                Text("Tap a row to select. Tap ▶ to preview.")
            }
            Section {
                TextField("e.g. A dry, deadpan British observational comedian.", text: $role, axis: .vertical)
                    .lineLimit(2 ... 4)
            } header: {
                Text("Role")
            } footer: {
                Text("Their function or relationship to you (coach, friend, prosecutor). Goes into the prompt.")
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
                Text("Backstory")
            } footer: {
                Text("Their life context — where they're from, what they've done. Shapes how they think.")
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
                Picker("Pace", selection: $paceChoice) {
                    Text("None").tag("")
                    ForEach(paceOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                Picker("Length", selection: $verbosityChoice) {
                    Text("None").tag("")
                    ForEach(verbosityOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                TextField("Or describe in your own words", text: $conversationalCustom, axis: .vertical)
                    .lineLimit(1 ... 3)
            } header: {
                Text("Conversational style")
            } footer: {
                Text("Pace = how fast they talk. Length = how much they say. Pick one or both, or write your own.")
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            guard !didPrefill else { return }
            didPrefill = true
            prefill()
        }
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
        var remaining = persona.conversationalStyle ?? ""
        for pace in paceOptions {
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
        for v in verbosityOptions {
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

    private func loadVoices() async {
        do {
            voices = try await api.getVoices()
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
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
