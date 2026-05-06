import SwiftData
import SwiftUI

// TERMINOLOGY:
// - `@Query` = Fetches data from SwiftData (the local database) reactively.
//   Like a live database query that auto-updates the UI when data changes.
//   Similar to React Query / SWR but for local SQLite.
// - `ForEach` = SwiftUI's map() — iterates over a collection to render views.
// - `List` = A scrollable list with built-in swipe-to-delete, separators, etc.
//   Like a FlatList in React Native.

/// Shows past conversations with timestamps.
struct HistoryView: View {
    // Fetch all conversations from the database, sorted by most recent first.
    // `\Conversation.updatedAt` is a "key path" — like a property accessor reference.
    // In TS it would be: (c: Conversation) => c.updatedAt
    @Query(sort: \Conversation.updatedAt, order: .reverse)
    private var conversations: [Conversation]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            if conversations.isEmpty {
                // `ContentUnavailableView` = a standard empty-state placeholder
                ContentUnavailableView(
                    "No Conversations Yet",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Start a conversation to see it here.")
                )
            } else {
                ForEach(conversations) { conversation in
                    NavigationLink {
                        ConversationDetailView(conversation: conversation)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conversation.title.isEmpty ? "Untitled" : conversation.title)
                                .font(.headline)
                            Text(conversation.updatedAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(conversation.messages.count) messages")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                // `.onDelete` adds swipe-to-delete gesture (built into List)
                .onDelete { indexSet in
                    for index in indexSet {
                        modelContext.delete(conversations[index])
                    }
                }
            }
        }
        .navigationTitle("History")
    }
}

/// Shows all messages in a single conversation.
struct ConversationDetailView: View {
    let conversation: Conversation

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(conversation.sortedMessages) { message in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: message.role == .user ? "person.fill" : "bubble.left.fill")
                            .foregroundStyle(message.role == .user ? .blue : .green)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.role == .user ? "You" : "Tutor")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(message.content)
                                .font(.body)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(conversation.title.isEmpty ? "Conversation" : conversation.title)
    }
}
