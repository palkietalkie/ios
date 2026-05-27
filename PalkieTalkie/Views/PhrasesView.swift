import SwiftUI

struct PhrasesView: View {
    @State private var phrases: [PhraseUsage] = []

    var body: some View {
        List(phrases) { phrase in
            VStack(alignment: .leading, spacing: 4) {
                Text(phrase.phrase).font(.headline)
                Text("Used \(phrase.count)×").font(.caption).foregroundStyle(.secondary)
                if !phrase.alternatives.isEmpty {
                    Text("Try: " + phrase.alternatives.joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(.blue)
                }
            }
        }
        .navigationTitle("Frequent phrases")
        .task {
            phrases = await (try? BackendAPI.shared.getPhrases()) ?? []
        }
    }
}
