import Foundation

/// Server-side contract for the conversation start handshake. Backend assembles the persona text prompt and selects an
/// inference provider via the `INFERENCE_PROVIDER` env var. `provider == "personaplex"` returns NVIDIA's WS URL with
/// HMAC ticket + sampling defaults baked in; `provider == "openai"` returns the OpenAI Realtime WS URL + a short-lived
/// ephemeral token. iOS picks the wire protocol based on `provider`.
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

struct KGEntityDTO: Codable {
    let id: String
    let type: String
    let name: String
    let attrs: [String: String]
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
    let displayName: String?
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
    let displayName: String?
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

/// Auth seam. Production wires Clerk; tests pass a stub. `sessionToken()` throws so callers can distinguish "no session
/// at all" from "session present but token fetch failed transiently" — those used to be flattened to `nil` and surfaced
/// as an opaque "not signed in" to the user.
///
/// Reference type (`AnyObject`) so SwiftUI can hold it in `@Environment` without copying. Methods are async so the
/// production conformer (`ClerkAuthAdapter`) can hop to MainActor internally without forcing every callsite onto it.
/// `userId` / `email` getters are async for the same reason — Clerk's user state lives on `@MainActor`.
protocol Authing: AnyObject, Sendable {
    var userId: String? { get async }
    var email: String? { get async }
    func sessionToken() async throws -> String
    func signOut() async
}

struct AuthTokenError: Error {
    let reason: String
}

/// Networking seam — same shape as URLSession.data(for:). Renamed from HTTPTransport to align with the constructor-
/// injected style introduced when the BackendAPI singleton was removed.
protocol Transport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: Transport {}

/// Pure transport: builds requests, attaches auth, encodes JSON (snake_case), decodes responses. No feature methods —
/// those live in `BackendEndpoints`. Used to be an `actor` with a singleton; now a constructor-injected `final class`
/// so SwiftUI views and tests can hand in their own transport / auth. `Observable` lets it ride in `@Environment`.
@Observable
final class BackendAPI: @unchecked Sendable {
    let baseURL: URL
    @ObservationIgnored private let transport: any Transport
    @ObservationIgnored private let auth: any Authing

    init(
        baseURL: URL? = nil,
        transport: any Transport,
        auth: any Authing,
    ) {
        if let baseURL {
            self.baseURL = baseURL
        } else {
            // Info.plist's BACKEND_URL is per-config baked at build time by xcodegen (Debug = dev Fly app, Release = prd). Missing / wrong-type / unparseable value means project.yml + Info.plist drifted; crash on the first launch rather than silently dialing the wrong host.
            guard
                let urlString = Bundle.main.object(forInfoDictionaryKey: "BACKEND_URL") as? String,
                let parsed = URL(string: urlString)
            else {
                fatalError("Info.plist BACKEND_URL is missing or unparseable — check project.yml settings.configs")
            }
            self.baseURL = parsed
        }
        self.transport = transport
        self.auth = auth
    }

    // MARK: - Public transport surface (used by BackendEndpoints)

    func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: urlForPath(path))
        request.httpMethod = "GET"
        try await attachAuth(&request)
        return try await execute(request)
    }

    func post<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        var request = URLRequest(url: urlForPath(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await attachAuth(&request)
        request.httpBody = try Self.encoder.encode(body)
        return try await execute(request)
    }

    /// Raw-bytes POST. Used by session-audio upload: the body is a gzipped wav, not JSON. Caller sets Content-Type (e.g. "audio/wav+gzip") so the backend can record the format for later decode.
    func postRaw(_ path: String, body: Data, contentType: String) async throws {
        var request = URLRequest(url: urlForPath(path))
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        try await attachAuth(&request)
        request.httpBody = body
        _ = try await executeRaw(request)
    }

    func patch<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        var request = URLRequest(url: urlForPath(path))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await attachAuth(&request)
        request.httpBody = try Self.encoder.encode(body)
        return try await execute(request)
    }

    func put<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        var request = URLRequest(url: urlForPath(path))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await attachAuth(&request)
        request.httpBody = try Self.encoder.encode(body)
        return try await execute(request)
    }

    func delete<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: urlForPath(path))
        request.httpMethod = "DELETE"
        try await attachAuth(&request)
        return try await execute(request)
    }

    // MARK: - Encoding / decoding (single source of truth for snake_case mapping)

    /// Backend uses snake_case JSON; Swift uses camelCase property names. Single encoder/decoder configured here is the
    /// only place this conversion lives.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    struct EmptyResponse: Decodable {}

    // MARK: - Private helpers

    /// Allow caller paths to include a query string (e.g. `/stats/cefr?level=B1`).
    /// `URL.appendingPathComponent` would percent-encode the `?`, so route through `URLComponents` to keep the query
    /// intact.
    func urlForPath(_ path: String) -> URL {
        if let queryStart = path.firstIndex(of: "?") {
            let pathOnly = String(path[..<queryStart])
            let query = String(path[path.index(after: queryStart)...])
            var components = URLComponents(
                url: baseURL.appendingPathComponent(pathOnly),
                resolvingAgainstBaseURL: false,
            )
            components?.query = query
            if let url = components?.url { return url }
        }
        return baseURL.appendingPathComponent(path)
    }

    private func attachAuth(_ request: inout URLRequest) async throws {
        do {
            let token = try await auth.sessionToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } catch let error as AuthTokenError {
            throw BackendError.notAuthenticated(reason: error.reason)
        } catch {
            throw BackendError.notAuthenticated(reason: String(describing: error))
        }
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.http(0, "no response")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw BackendError.http(http.statusCode, body)
        }
        if T.self == EmptyResponse.self, let empty = EmptyResponse() as? T {
            return empty
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw BackendError.decoding(String(describing: error))
        }
    }

    /// execute() variant for endpoints that don't return JSON (204 No Content, raw body uploads). Just validates the status code and returns the bytes.
    private func executeRaw(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.http(0, "no response")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw BackendError.http(http.statusCode, body)
        }
        return data
    }
}
