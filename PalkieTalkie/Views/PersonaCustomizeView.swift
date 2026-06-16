import SwiftUI

@MainActor
struct PersonaCustomizeView: View {
    @Environment(\.backendAPI) private var api
    @Environment(\.dismiss) private var dismiss
    @State private var model: PersonaCustomizeViewModel
    @State private var preview = VoicePreviewPlayer()

    init(persona: PersonaDTO?) {
        _model = State(initialValue: PersonaCustomizeViewModel(persona: persona))
    }

    @ViewBuilder
    private func voiceRow(_ voice: VoiceDTO) -> some View {
        let isSelected = model.voiceId == voice.id
        let hasPreview = VoicePreviewPlayer.hasPreview(voice.id)
        let isPlaying = preview.nowPlaying == voice.id
        HStack {
            Button {
                model.voiceId = voice.id
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
                Text(verbatim: "-")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Preview unavailable")
            }
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("e.g. Riley", text: $model.name)
            } header: {
                Text("Name")
            } footer: {
                Text("Shown in your persona library and used as the character's name in conversation.")
            }
            Section {
                TextField("One-liner shown in your library", text: $model.personaDescription, axis: .vertical)
                    .lineLimit(2 ... 4)
            } header: {
                Text("Tagline")
            } footer: {
                Text("Library preview text. Not sent to the AI.")
            }
            Section {
                if model.voices.isEmpty {
                    ProgressView()
                } else {
                    ForEach(model.voices) { voice in
                        voiceRow(voice)
                    }
                }
            } header: {
                Text("Voice")
            } footer: {
                Text("Tap a row to select. Tap ▶ to preview.")
            }
            Section {
                TextField("e.g. A dry, deadpan British observational comedian.", text: $model.role, axis: .vertical)
                    .lineLimit(2 ... 4)
            } header: {
                Text("Role")
            } footer: {
                Text("Their function or relationship to you (coach, friend, prosecutor). Goes into the prompt.")
            }
            Section {
                TextField("e.g. Late 20s, 40s, 70s", text: $model.age)
            } header: {
                Text("Age")
            } footer: {
                Text("Drives pacing and word choice indirectly. Free text.")
            }
            Section {
                TextField(
                    "e.g. Lives in SF, works at an early-stage startup.",
                    text: $model.background,
                    axis: .vertical,
                )
                .lineLimit(2 ... 4)
            } header: {
                Text("Backstory")
            } footer: {
                Text("Their life context: where they're from, what they've done. Shapes how they think.")
            }
            Section {
                Picker("Style", selection: $model.vocabularyChoice) {
                    Text("None").tag("")
                    ForEach(PersonaCustomizeViewModel.vocabularyOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                TextField("Or describe in your own words", text: $model.vocabularyCustom, axis: .vertical)
                    .lineLimit(1 ... 3)
            } header: {
                Text("Vocabulary")
            } footer: {
                Text("Pick a style, write your own, or both.")
            }
            Section {
                Picker("Pace", selection: $model.paceChoice) {
                    Text("None").tag("")
                    ForEach(PersonaCustomizeViewModel.paceOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                Picker("Length", selection: $model.verbosityChoice) {
                    Text("None").tag("")
                    ForEach(PersonaCustomizeViewModel.verbosityOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                TextField("Or describe in your own words", text: $model.conversationalCustom, axis: .vertical)
                    .lineLimit(1 ... 3)
            } header: {
                Text("Conversational style")
            } footer: {
                Text("Pace = how fast they talk. Length = how much they say. Pick one or both, or write your own.")
            }
            Section {
                TextField("e.g. Product design, hikes, coffee shops.", text: $model.topicalPreferences, axis: .vertical)
                    .lineLimit(1 ... 3)
            } header: {
                Text("Topics they bring up")
            } footer: {
                Text("What they ask about, what they steer toward.")
            }
            Section {
                Toggle("Share with community", isOn: $model.isPublic)
            } footer: {
                Text("Public personas appear in everyone's persona library. They can like and use yours.")
            }
            Section {
                Button(model.persona == nil ? "Create" : "Save", action: { Task { await model.save(api: api) } })
                    .disabled(model.name.isEmpty || model.saving)
            }
        }
        .navigationTitle(model.persona == nil ? "New persona" : "Edit persona")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear { model.prefill() }
        .task { await model.loadVoices(api: api) }
        .alert(
            "Couldn't save",
            isPresented: Binding(get: { model.saveError != nil }, set: { if !$0 { model.saveError = nil } }),
        ) {
            Button("OK") { model.saveError = nil }
        } message: {
            Text(model.saveError ?? "")
        }
        .onChange(of: model.didSaveSuccessfully) { _, newValue in
            if newValue { dismiss() }
        }
    }
}
