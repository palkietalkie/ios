import ClerkKit
import SwiftUI

@MainActor
struct ProfileView: View {
    @State private var email: String = ""
    @State private var displayName: String = ""
    @State private var namePronunciation: String = ""
    @State private var nativeLanguage: String = ""
    @State private var targetAccent: String = ""
    @State private var goals: String = ""
    @State private var knowledgeGraph: [KGEntityDTO] = []
    @State private var saveError: String?
    @State private var loaded: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    LabeledContent("Email") {
                        Text(email.isEmpty
                            ? (Clerk.shared.user?.primaryEmailAddress?.emailAddress ?? "—")
                            : email)
                    }
                    TextField("Display name", text: $displayName)
                    TextField("Name pronunciation (e.g. WESS, NEE-shee-oh)", text: $namePronunciation)
                    TextField("Native language", text: $nativeLanguage)
                    TextField("Target accent", text: $targetAccent)
                    TextField("Goals", text: $goals, axis: .vertical)
                }
                Section("Knowledge Graph (read-only)") {
                    if knowledgeGraph.isEmpty {
                        Text(
                            "No entities yet. As you talk, the AI starts recognizing the people, places, and projects."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    } else {
                        ForEach(knowledgeGraph, id: \.id) { entity in
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
                Section("History") {
                    NavigationLink("Past conversations") { HistoryView() }
                }
                Section {
                    Button("Save changes") {
                        Task { await save() }
                    }
                    .disabled(!loaded)
                    if let saveError {
                        Text(saveError).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await ClerkAuth.shared.signOut() }
                    }
                }
            }
            .navigationTitle("Profile")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        do {
            let profile = try await BackendAPI.shared.getProfile()
            email = profile.email ?? ""
            displayName = profile.displayName ?? ""
            namePronunciation = profile.namePronunciation ?? ""
            nativeLanguage = profile.nativeLanguage ?? ""
            targetAccent = profile.targetAccent ?? ""
            goals = profile.goals ?? ""
            loaded = true
        } catch {
            saveError = error.localizedDescription
        }
        knowledgeGraph = await (try? BackendAPI.shared.getKG()) ?? []
    }

    private func save() async {
        let update = ProfileUpdate(
            displayName: displayName.isEmpty ? nil : displayName,
            namePronunciation: namePronunciation.isEmpty ? nil : namePronunciation,
            nativeLanguage: nativeLanguage.isEmpty ? nil : nativeLanguage,
            targetAccent: targetAccent.isEmpty ? nil : targetAccent,
            goals: goals.isEmpty ? nil : goals,
            locationCity: nil,
            timezone: TimeZone.current.identifier
        )
        do {
            _ = try await BackendAPI.shared.updateProfile(update)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
