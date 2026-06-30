import SwiftUI

struct PhrasesView: View {
    private static let cacheKey = "cache.phrases"
    @Environment(\.backendAPI) private var api
    @State private var phrases: [PhraseUsage] = JSONCache.load([PhraseUsage].self, key: PhrasesView.cacheKey) ?? []
    @State private var loadError: String?

    var body: some View {
        List {
            if let loadError {
                Text("Couldn't refresh phrases: \(loadError)")
                    .font(.footnote).foregroundStyle(.red).textSelection(.enabled)
            }
            ForEach(phrases) { phrase in
                VStack(alignment: .leading, spacing: 4) {
                    Text(phrase.phrase).font(.headline)
                    Text("Used \(phrase.count)×").font(.caption).foregroundStyle(.secondary)
                    if !phrase.alternatives.isEmpty {
                        Text("Try: \(phrase.alternatives.joined(separator: ", "))")
                            .font(.footnote)
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
        .navigationTitle("Frequent phrases")
        .task {
            // Keep the cached list on failure, but surface the error instead of `try?`-swallowing it silently.
            do {
                let fresh = try await api.getPhrases()
                phrases = fresh
                JSONCache.save(fresh, key: Self.cacheKey)
                loadError = nil
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}
