import ClerkKit
import SwiftUI

@MainActor
struct ProfileView: View {
    @Environment(\.backendAPI) private var api
    @Environment(\.authing) private var auth
    @State private var model = ProfileViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    LabeledContent("Email") {
                        Text(model.email.isEmpty
                            ? (Clerk.shared.user?.primaryEmailAddress?.emailAddress ?? "—")
                            : model.email)
                    }
                    LabeledContent("Preferred name") {
                        TextField("e.g. Wes", text: $model.preferredName)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Pronunciation") {
                        TextField("e.g. WESS", text: $model.namePronunciation)
                            .multilineTextAlignment(.trailing)
                    }
                    // Distinct sub-row so the user can clearly tell this is a SUGGESTION (not the stored value) and tap to accept. Ghost-text placeholder reads identically to a real value to most users.
                    if model.namePronunciation.isEmpty, !model.pronunciationSuggestion.isEmpty {
                        Button {
                            model.namePronunciation = model.pronunciationSuggestion
                        } label: {
                            HStack {
                                Text("Suggested:").foregroundStyle(.secondary)
                                Text(model.pronunciationSuggestion).bold()
                                Spacer()
                                Text("Tap to use").font(.caption).foregroundStyle(.tint)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    NavigationLink {
                        MultiLanguagePicker(
                            languages: model.languages,
                            selection: $model.nativeLanguages,
                            title: "Native languages",
                        )
                    } label: {
                        LabeledContent("Native languages") {
                            Text(model.nativeLanguages.isEmpty
                                ? String(localized: "Choose…")
                                : model.nativeLanguages.sorted().joined(separator: ", "))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                Section("Knowledge Graph (read-only)") {
                    if let kgError = model.kgError {
                        Text("Couldn't load your knowledge graph: \(kgError)")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                    if model.knowledgeGraph.isEmpty {
                        Text(
                            "No entities yet. As you talk, the AI starts recognizing the people, places, and projects.",
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.knowledgeGraph, id: \.id) { entity in
                            VStack(alignment: .leading) {
                                Text(entity.name).font(.headline)
                                Text(entity.type.capitalized).font(.caption).foregroundStyle(.secondary)
                                ForEach(entity.attrs.sorted(by: { $0.key < $1.key }), id: \.key) { pair in
                                    Text("\(pair.key): \(pair.value)").font(.caption2)
                                }
                            }
                        }
                    }
                }
                Section {
                    Button {
                        Task { await model.save(api: api) }
                    } label: {
                        HStack {
                            if model.saving {
                                ProgressView().controlSize(.small)
                            }
                            Text(model.saving ? "Saving…" : "Save changes")
                            Spacer()
                            if let savedAt = model.savedAt, Date().timeIntervalSince(savedAt) < 3 {
                                Label("Saved", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .labelStyle(.iconOnly)
                                    .transition(.opacity)
                            }
                        }
                        // View-side animation. The VM stays SwiftUI-agnostic (no withAnimation call) so it's safe to instantiate + drive from XCTest without going through SwiftUI's animation runtime — that runtime crashes when invoked outside a real render context.
                        .animation(.default, value: model.savedAt)
                    }
                    .disabled(!model.loaded || model.saving)
                    if let saveError = model.saveError {
                        Text(saveError).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        let auth = auth
                        Task { await auth.signOut() }
                    }
                }
            }
            .navigationTitle("Profile")
            .task {
                guard !model.didInitialLoad else { return }
                model.didInitialLoad = true
                await model.load(api: api)
            }
            .refreshable { await model.load(api: api) }
        }
    }
}
