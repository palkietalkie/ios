import SwiftUI

/// First-launch Privacy & Data screen. Shown until the user makes a choice (consent status reports `set=false`). Both toggles default to false — opt-in, not opt-out. User can flip them again later in More → Privacy & Data.
@MainActor
struct ConsentView: View {
    let onContinue: () -> Void
    @Environment(\.backendAPI) private var api
    @State private var personalization: Bool = true
    @State private var productImprovement: Bool = true
    @State private var saving: Bool = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "Palkie Talkie remembers what you say so the AI feels like a friend who knows you. We also want to use your conversations to make the product better.",
                    )
                    .font(.body)
                    Text("You decide. Change either at any time in More → Privacy & Data.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Personalize my experience", isOn: $personalization)
                } footer: {
                    Text(
                        "Your transcripts feed memory of you (knowledge graph, last-session recall). Off = every conversation starts cold.",
                    )
                }
                Section {
                    Toggle("Help improve Palkie Talkie", isOn: $productImprovement)
                } footer: {
                    Text(
                        "Your conversations contribute to model + pipeline improvements. Stored under your account, never sold to third parties.",
                    )
                }
                Section {
                    Button(action: { Task { await submit() } }) {
                        if saving { ProgressView() } else { Text("Continue") }
                    }
                    .disabled(saving)
                }
            }
            .navigationTitle("Privacy & Data")
            .alert("Couldn't save", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func submit() async {
        saving = true
        defer { saving = false }
        do {
            _ = try await api.setConsent(
                ConsentUpdatePayload(
                    personalization: personalization,
                    productImprovement: productImprovement,
                ),
            )
            onContinue()
        } catch let err {
            error = err.localizedDescription
        }
    }
}
