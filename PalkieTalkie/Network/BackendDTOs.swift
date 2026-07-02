import Foundation

// Wire types WITHOUT a generated counterpart live here; everything the backend exposes as a named OpenAPI component is generated into Generated/APITypes.swift (with iOS-name aliases in APITypesConformances.swift). These remain hand-written because the backend returns them as inline/anonymous schemas (KG, recall) or because they're client-side view-models, not server payloads.

/// One item under a "Today" section, as the UI consumes it. View-model, not a wire type: built in `getTalkAboutToday` from the generated `ItemOut` with a composed, stable `id` for SwiftUI lists.
struct TalkItem: Codable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let source: String
    let imageUrl: String
    /// Source article URL, for attribution / a future "read full story" link. NOT used to make the model fetch.
    let url: String?
    /// Full article body, fetched server-side so the topic prompt carries real depth instead of the one-line summary. Empty/nil for quizzes.
    let details: String?
}

/// One labeled section on the Today screen. `topic` is the slug ("politics", "business", "sports", "quizzes"); the UI looks up the localized header from xcstrings via `topic.capitalized`.
struct TalkSection: Codable, Identifiable {
    let topic: String
    let items: [TalkItem]
    var id: String {
        topic
    }
}

/// One node in the knowledge graph. Backend returns `/kg` nodes as untyped objects (OpenAPI sees only `[String: String]`), so this typed shape can't be generated. Wire shape owned by `app/services/neo4j/fetch_kg.py`: id/type/name/attrs, attrs stringified.
struct KGEntityDTO: Codable {
    let id: String
    let type: String
    let name: String
    let attrs: [String: String]
}

/// One relation in the knowledge graph (a → b). Not rendered yet; decoded so the full `{nodes, edges}` payload round-trips and the contract stays honest.
struct KGEdgeDTO: Codable, Identifiable {
    let src: String
    let rel: String
    let dst: String
    var id: String {
        "\(src)|\(rel)|\(dst)"
    }
}

/// Full `/kg` response. Backend returns `{nodes, edges}`; the earlier iOS code decoded a bare `[KGEntityDTO]`, which silently failed to decode and showed every user an empty KG even when the graph had data.
struct KGGraphDTO: Codable {
    let nodes: [KGEntityDTO]
    let edges: [KGEdgeDTO]
}

/// Conversation-time recall payloads. Shapes match `backend/app/routers/recall.py` (returned inline, not as named components).
struct RecallRelationDTO: Codable {
    let rel: String?
    let target: String
}

struct RecallEntityDTO: Codable {
    let name: String
    let type: String
    let relations: [RecallRelationDTO]
}

struct RecallFactsDTO: Codable {
    let entities: [RecallEntityDTO]
}

struct RecallConversationsDTO: Codable {
    let snippets: [String]
}

struct RecallTurnDTO: Codable {
    let speaker: String
    let text: String
    let when: String
}

struct RecallTranscriptsDTO: Codable {
    let turns: [RecallTurnDTO]
}

struct WebFetchDTO: Codable {
    let content: String
}

/// The user's here-and-now, assembled client-side and partially sent on `/conversation/start`. Carries the device GPS fix and reverse-geocoded city alongside the clock + calendar. Not a server payload component: only `topic_override` crosses the wire (see `startConversation`); the rest (including location/city) is kept client-side for a future feature and re-derived server-side from the stored profile + integrations.
struct ConversationContext: Codable {
    let localISOTime: String
    let timezone: String
    let lat: Double?
    let lon: Double?
    let city: String?
    let calendarEvents: [CalendarEventDTO]
}

struct CalendarEventDTO: Codable {
    let title: String
    let startISO: String
    let endISO: String
    let location: String?
}

enum BackendError: Error, Equatable, LocalizedError {
    case invalidURL
    case notAuthenticated(reason: String)
    case http(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid backend URL"
        case let .notAuthenticated(reason):
            "Not signed in (\(reason))"
        case let .http(status, body):
            "HTTP \(status): \(body.prefix(200))"
        case let .decoding(detail):
            "Couldn't decode response: \(detail.prefix(200))"
        }
    }
}
