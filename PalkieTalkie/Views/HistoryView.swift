import SwiftUI

@MainActor
struct HistoryView: View {
    @State private var sessions: [SessionSummary] = []
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            List(sessions) { session in
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.personaId ?? "Unknown persona").font(.headline)
                    HStack {
                        Text(session.startedAt, style: .date)
                        Text(session.startedAt, style: .time)
                        Spacer()
                        if let seconds = session.durationSeconds {
                            Text("\(seconds / 60)m \(seconds % 60)s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .task { await load() }
            .refreshable { await load() }
            .overlay {
                if sessions.isEmpty, loadError == nil {
                    ContentUnavailableView("No sessions yet", systemImage: "clock.arrow.circlepath")
                }
            }
            .alert("Couldn't load history", isPresented: .constant(loadError != nil)) {
                Button("OK") { loadError = nil }
            } message: {
                Text(loadError ?? "")
            }
        }
    }

    private func load() async {
        do {
            sessions = try await BackendAPI.shared.getSessions()
        } catch {
            loadError = error.localizedDescription
        }
    }
}
