import SwiftUI

struct PhrasesView: View {
    private static let cacheKey = "cache.phrases"
    @Environment(\.backendAPI) private var api
    @State private var phrases: [PhraseUsage] = JSONCache.load([PhraseUsage].self, key: PhrasesView.cacheKey) ?? []

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
            if let fresh = try? await api.getPhrases() {
                phrases = fresh
                JSONCache.save(fresh, key: Self.cacheKey)
            }
        }
    }
}
