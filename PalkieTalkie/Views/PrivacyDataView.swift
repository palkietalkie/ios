import SwiftUI

@MainActor
struct PrivacyDataView: View {
    @Environment(\.backendAPI) private var api
    @State private var personalization: Bool = false
    @State private var productImprovement: Bool = false
    @State private var loaded: Bool = false
    @State private var saving: Bool = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Toggle("Personalize my experience", isOn: $personalization)
                    .onChange(of: personalization) { _, _ in Task { await save() } }
            } footer: {
                Text(
                    "Your transcripts power memory of you (knowledge graph + last-session recall + future lifetime memory). Off = every conversation starts cold.",
                )
            }
            Section {
                Toggle("Help improve Palkie Talkie", isOn: $productImprovement)
                    .onChange(of: productImprovement) { _, _ in Task { await save() } }
            } footer: {
                Text(
                    "Your conversations contribute to model + pipeline improvements (mistake detection, persona tuning, training data for our own future models). Stored under your account, never sold to third parties.",
                )
            }
            Section {
                NavigationLink("Delete my conversation history") {
                    Text("Coming soon.").padding()
                }
                NavigationLink("Export my data") {
                    Text("Coming soon.").padding()
                }
                NavigationLink("Delete my account") {
                    Text("Coming soon.").padding()
                }
            }
        }
        .navigationTitle("Privacy & Data")
        .task {
            await load()
        }
        .alert("Couldn't save", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func load() async {
        do {
            let current = try await api.getConsent()
            personalization = current.personalization
            productImprovement = current.productImprovement
            loaded = true
        } catch let err {
            error = err.localizedDescription
        }
    }

    private func save() async {
        guard loaded, !saving else { return }
        saving = true
        defer { saving = false }
        do {
            _ = try await api.setConsent(
                ConsentUpdatePayload(
                    personalization: personalization,
                    productImprovement: productImprovement,
                ),
            )
        } catch let err {
            error = err.localizedDescription
        }
    }
}
