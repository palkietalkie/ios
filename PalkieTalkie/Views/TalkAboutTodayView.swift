import SwiftUI

struct TalkAboutTodayView: View {
    @Environment(SessionController.self) private var session
    @Environment(\.backendAPI) private var api
    /// Closure invoked when the user taps a topic card. The parent (MainTabView) uses it to switch the selected tab to .talk so the user actually sees the conversation they just kicked off. Default no-op keeps previews + unit tests working without wiring.
    var onTopicSelected: () -> Void = {}
    private static let cacheKey = "cache.talk_about_today"
    @State private var sections: [TalkSection] = JSONCache
        .load([TalkSection].self, key: TalkAboutTodayView.cacheKey) ?? []
    @State private var loadError: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(resolveHeaderKey(for: section.topic))
                                .font(.title3.bold())
                                .padding(.horizontal)
                            InfiniteHorizontalCarousel(items: section.items, cardHeight: 180) { item in
                                buildCard(item)
                            }
                        }
                    }
                    if let loadError {
                        Text(loadError)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Today")
            .refreshable { await load() }
            .overlay {
                if isLoading, sections.isEmpty { ProgressView() }
            }
            .task { await load() }
        }
    }

    /// Map topic slug → localized header. Slugs are owned by backend (constants.TOPICS); xcstrings carries the locale-aware display string. Unknown slugs render as the slug itself so the UI never blanks out on a server-side addition that iOS hasn't picked up a string for yet.
    private func resolveHeaderKey(for topic: String) -> LocalizedStringKey {
        switch topic {
        case "politics": "Politics"
        case "business": "Business"
        case "sports": "Sports"
        case "quizzes": "Quizzes"
        default: LocalizedStringKey(topic.prefix(1).uppercased() + topic.dropFirst())
        }
    }

    private func buildCard(_ item: TalkItem) -> some View {
        Button {
            session.startContextOverride = item.title + " — " + item.summary
            onTopicSelected()
            Task { await session.start() }
        } label: {
            ZStack(alignment: .bottomLeading) {
                buildImageBackground(for: item)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    if !item.source.isEmpty {
                        Text(item.source)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.55))
            }
            .frame(width: 260)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func buildImageBackground(for item: TalkItem) -> some View {
        Group {
            if let url = URL(string: item.imageUrl), !item.imageUrl.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    default:
                        placeholderBackground
                    }
                }
            } else {
                placeholderBackground
            }
        }
        // Pin the image to the card's footprint and clip overflow. Without this, AsyncImage's intrinsic image size (e.g. 1200pt) can leak into the ZStack's layout — the text VStack then positions itself within that oversized layout and the outer `.frame(width: 260)` shows only a center slice, making the title appear cut on both sides.
        .frame(width: 260, height: 180)
        .clipped()
    }

    private var placeholderBackground: some View {
        LinearGradient(
            colors: [Color(.systemGray3), Color(.systemGray2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing,
        )
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await api.getTalkAboutToday()
            sections = fresh
            JSONCache.save(fresh, key: Self.cacheKey)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}
