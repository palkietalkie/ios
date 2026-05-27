import SwiftUI

struct MistakesView: View {
    @State private var mistakes: [Mistake] = []
    @State private var loadError: String?

    var body: some View {
        List(mistakes) { mistake in
            VStack(alignment: .leading, spacing: 4) {
                Text(mistake.original).foregroundStyle(.red).strikethrough()
                Text(mistake.correction).foregroundStyle(.green).font(.headline)
                Text("Seen \(mistake.count)×").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Mistakes")
        .task {
            do {
                mistakes = try await BackendAPI.shared.getMistakes()
            } catch {
                loadError = error.localizedDescription
            }
        }
        .overlay {
            if mistakes.isEmpty {
                ContentUnavailableView("No mistakes recorded yet", systemImage: "checkmark.seal")
            }
        }
    }
}
