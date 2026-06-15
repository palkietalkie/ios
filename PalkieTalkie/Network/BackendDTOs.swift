import Foundation

/// Server-side contract for the conversation start handshake. Backend assembles the persona text prompt and selects an inference provider via the `INFERENCE_PROVIDER` env var. `provider == "personaplex"` returns NVIDIA's WS URL with HMAC ticket + sampling defaults baked in; `provider == "openai"` returns the OpenAI Realtime WS URL + a short-lived ephemeral token. iOS picks the wire protocol based on `provider`.
struct StartResponse: Codable {
    let sessionId: String
    let textPrompt: String
    let voiceId: String
    let wsUrl: String
    let provider: String
    let ephemeralToken: String?
}

struct EndResponse: Codable {
    let sessionId: String
    let durationSeconds: Int
}

struct SessionSummary: Codable, Identifiable {
    let sessionId: String
    let personaId: String?
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int?

    var id: String {
        sessionId
    }
}

struct PersonaDTO: Codable {
    let id: String
    let name: String
    let description: String
    let voiceId: String
    let role: String?
    let age: String?
    let background: String?
    let vocabularyRegister: String?
    let conversationalStyle: String?
    let topicalPreferences: String?
    let isPreset: Bool
    let isPublic: Bool
    let isOwner: Bool
    let likeCount: Int
    let likedByMe: Bool
}

struct PersonaCreatePayload: Codable {
    let name: String
    let description: String
    let voiceId: String
    let role: String?
    let age: String?
    let background: String?
    let vocabularyRegister: String?
    let conversationalStyle: String?
    let topicalPreferences: String?
    let isPublic: Bool
}

struct PersonaUpdatePayload: Codable {
    let name: String?
    let description: String?
    let voiceId: String?
    let role: String?
    let age: String?
    let background: String?
    let vocabularyRegister: String?
    let conversationalStyle: String?
    let topicalPreferences: String?
    let isPublic: Bool?
}

struct VoiceDTO: Codable, Identifiable {
    let id: String
    let label: String
    let gender: String
    let description: String
}

struct ConsentDTO: Codable {
    let personalization: Bool
    let productImprovement: Bool
    let set: Bool
}

struct ConsentUpdatePayload: Codable {
    let personalization: Bool
    let productImprovement: Bool
}

struct CEFRCoverage: Codable, Identifiable {
    var id: String {
        level
    }

    let level: String
    let totalWords: Int
    let usedWords: Int
    let coveragePct: Double
}

struct Stats: Codable {
    let dayStreak: Int
    let sessionTotalSeconds: Int
    let sessionsCount: Int
    let uniqueWords: Int
    let uniquePhrases: Int
    let userTalkPct: Double?
    let speakingRateWpm: Double?
    let pitchRangeHz: Double?
    let cefrCoverage: [CEFRCoverage]
}

struct Mistake: Codable, Identifiable {
    let id: String
    let original: String
    let correction: String
    let count: Int
}

struct PhraseUsage: Codable, Identifiable {
    let id: String
    let phrase: String
    let count: Int
    let alternatives: [String]
}

struct CEFRWord: Codable, Identifiable {
    let id: String
    let word: String
    let frequencyRank: Int
    let used: Bool
}

struct Entitlement: Codable {
    let isPremium: Bool
    let freeMinutesRemainingToday: Int
    let freeMinutesRemainingThisWeek: Int
    /// Caps themselves — backend exposes them so the iOS UI doesn't hard-code numbers that can drift from `app/routers/entitlement/constants.py`.
    let freeMinutesPerDayCap: Int
    let freeMinutesPerWeekCap: Int
    let premiumEndsAt: Date?
}

/// One item under a "Today" section. Backend hands every section the same shape regardless of topic (news headline vs quiz question). News items populate `source` and `imageUrl`; quiz items leave both empty.
struct TalkItem: Codable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let source: String
    let imageUrl: String
}

/// One labeled section on the Today screen. `topic` is the slug ("politics", "business", "sports", "quizzes"); the UI looks up the localized header from xcstrings via `topic.capitalized`.
struct TalkSection: Codable, Identifiable {
    let topic: String
    let items: [TalkItem]
    var id: String {
        topic
    }
}

/// Mirrors backend's `DailyContentResponse`. New topics can be added server-side (constants.TOPICS) without changing this DTO.
struct DailyContentDTO: Codable {
    struct RawItem: Codable {
        let title: String
        let summary: String
        let source: String
        /// Backend sends snake_case `image_url`; the global JSONDecoder is configured with `convertFromSnakeCase`, which maps that to `imageUrl` automatically — no explicit CodingKeys needed (and adding them here would override the strategy).
        let imageUrl: String
    }

    struct RawSection: Codable {
        let topic: String
        let items: [RawItem]
    }

    let day: String
    let sections: [RawSection]
}

/// One node in the knowledge graph. Wire shape owned by the backend (`app/services/neo4j/fetch_kg.py`): id/type/name/attrs, attrs stringified. Keep in sync with that file and `BackendDTOsTests` KG decode contract test.
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

/// Conversation-time recall payloads. Shapes match `backend/app/routers/recall.py`.
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

struct ConversationContext: Codable {
    let localISOTime: String
    let timezone: String
    let lat: Double?
    let lon: Double?
    let city: String?
    let weatherDescription: String?
    let temperatureC: Double?
    let calendarEvents: [CalendarEventDTO]
}

struct CalendarEventDTO: Codable {
    let title: String
    let startISO: String
    let endISO: String
    let location: String?
}

struct ProfileDTO: Codable {
    let email: String?
    let preferredName: String?
    let namePronunciation: String?
    /// Placeholder suggestion computed server-side when `namePronunciation` is empty; iOS shows it as the TextField prompt so the user sees the AI's guess without it being committed. Never persisted client-side — only the user typing into the field stores anything.
    let namePronunciationSuggestion: String?
    let nativeLanguages: [String]
    let targetLanguage: String
    let targetAccents: [String]
    let proficiency: String
    let tutorSpeakingSpeed: String
    let goals: String?
    let locationCity: String?
    let timezone: String?
}

struct ProfileUpdate: Codable {
    let preferredName: String?
    let namePronunciation: String?
    let nativeLanguages: [String]?
    let targetLanguage: String?
    let targetAccents: [String]?
    let proficiency: String?
    let tutorSpeakingSpeed: String?
    let goals: String?
    let locationCity: String?
    let timezone: String?
}

struct LanguageDTO: Codable, Identifiable, Hashable {
    var id: String {
        name
    }

    let name: String
    let accents: [String]
}

struct PracticeOptionsDTO: Codable {
    let proficiency: [String]
    let tutorSpeakingSpeed: [String]
}

struct IntegrationStatus: Codable, Identifiable {
    var id: String {
        provider
    }

    let provider: String
    let connected: Bool
    let expiresAt: Date?
}

struct OAuthConnectURL: Codable {
    let authUrl: String
}

struct TranscriptAppend: Codable {
    let speaker: String // "user" | "persona"
    let text: String
    let startedAt: Date
    let endedAt: Date
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
