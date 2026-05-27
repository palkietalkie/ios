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
    let resetsAt: Date
}

struct TalkPrompt: Codable, Identifiable {
    let id: String
    let kind: String // "news" | "quiz"
    let title: String
    let summary: String
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
    let nativeLanguage: String?
    let targetAccent: String?
    let goals: String?
    let locationCity: String?
    let timezone: String?
}

struct ProfileUpdate: Codable {
    let displayName: String?
    let namePronunciation: String?
    let nativeLanguage: String?
    let targetAccent: String?
    let goals: String?
    let locationCity: String?
    let timezone: String?
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

/// Pluggable token source. Production wires Clerk's JWT; tests pass a stub.
/// Throws so callers can distinguish "no session at all" from "session present but token fetch failed transiently" —
/// those used to be flattened to `nil` and surfaced as an opaque "not signed in" to the user.
protocol AuthTokenProviding: Sendable {
    func sessionToken() async throws -> String
}

struct AuthTokenError: Error {
    let reason: String
}

/// Wrapper that hops to MainActor to read the Clerk JWT. Keeps `ClerkAuth` `@MainActor`-isolated while still letting
/// non-isolated callers (the `BackendAPI` actor) ask for a token without spelling out the hop.
struct ClerkAuthTokenProvider: AuthTokenProviding {
    func sessionToken() async throws -> String {
        try await ClerkAuth.shared.sessionToken()
    }
}

/// Networking seam — same shape as URLSession.data(for:).
protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

/// Pure transport: builds requests, attaches auth, encodes JSON (snake_case), decodes responses. No feature methods —
/// those live in `BackendEndpoints`.
actor BackendAPI {
    static let shared = BackendAPI()

    let baseURL: URL
    private let transport: HTTPTransport
    private let auth: AuthTokenProviding

    init(
        baseURL: URL? = nil,
        transport: HTTPTransport? = nil,
        auth: AuthTokenProviding? = nil
    ) {
        if let baseURL {
            self.baseURL = baseURL
        } else {
            // Coerce empty → nil so the fallback triggers. Xcode's Info.plist preprocessor doesn't understand
            // `${VAR:-default}` shell syntax (only `$(VAR)`), so when BACKEND_URL env var isn't exported at build time the key resolves to "" — without this guard, URL(string:"") is nil and the force-unwrap crashes the app at launch (e.g., during `xcodebuild test` where boot.sh's env exports don't run).
            let raw = Bundle.main.object(forInfoDictionaryKey: "BACKEND_URL") as? String
            let urlString = (raw?.isEmpty == false ? raw : nil) ?? "https://api.palkietalkie.com"
            self.baseURL = URL(string: urlString)!
        }
        if let transport {
            self.transport = transport
        } else {
            let config = URLSessionConfiguration.default
            config.waitsForConnectivity = false
            // 15s tolerates cold Clerk JWKS fetch + Neon warmup on endpoints like /stats that aren't on the
            // conversation-start hot path. Conversation-start latency budget (1.5s) is enforced via cold_start_complete
            // telemetry, not by failing the request — failing here would just show the user a misleading "timed out"
            // instead of letting the warmup tips UI run.
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 30
            self.transport = URLSession(configuration: config)
        }
        self.auth = auth ?? ClerkAuthTokenProvider()
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
                resolvingAgainstBaseURL: false
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
}
