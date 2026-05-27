import SwiftUI

struct TalkAboutTodayView: View {
    @Environment(SessionController.self) private var session
    @State private var prompts: [TalkPrompt] = []
    @State private var loadError: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                Section("News") {
                    ForEach(prompts.filter { $0.kind == "news" }) { row($0) }
                }
                Section("Quizzes") {
                    ForEach(prompts.filter { $0.kind == "quiz" }) { row($0) }
                }
                if let loadError {
                    Section { Text(loadError).foregroundStyle(.red).textSelection(.enabled) }
                }
            }
            .navigationTitle("What to talk about today")
            .refreshable { await load() }
            .overlay {
                if isLoading, prompts.isEmpty { ProgressView() }
            }
            .task { await load() }
        }
    }

    private func row(_ prompt: TalkPrompt) -> some View {
        Button {
            session.startContextOverride = prompt.title + " — " + prompt.summary
            Task { await session.start() }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(prompt.title).font(.headline).foregroundStyle(.primary)
                Text(prompt.summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            prompts = try await BackendAPI.shared.getTalkAboutToday()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}
