import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.palkietalkie", category: "mistakes")

struct MistakesView: View {
    private static let cacheKey = "cache.mistakes"
    @Environment(\.backendAPI) private var api
    @State private var mistakes: [Mistake] = JSONCache.load([Mistake].self, key: MistakesView.cacheKey) ?? []
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
                let fresh = try await api.getMistakes()
                mistakes = fresh
                JSONCache.save(fresh, key: Self.cacheKey)
            } catch {
                loadError = contentRefreshError(error, refreshing: "mistakes", log: logger)
            }
        }
        .overlay {
            if mistakes.isEmpty {
                ContentUnavailableView("No mistakes recorded yet", systemImage: "checkmark.seal")
            }
        }
    }
}
