import Foundation

/// Auth seam. Production wires Clerk; tests pass a stub. `sessionToken()` throws so callers can distinguish "no session at all" from "session present but token fetch failed transiently" — those used to be flattened to `nil` and surfaced as an opaque "not signed in" to the user.
///
/// Reference type (`AnyObject`) so SwiftUI can hold it in `@Environment` without copying. Methods are async so the production conformer (`ClerkAuthAdapter`) can hop to MainActor internally without forcing every callsite onto it. `userId` / `email` getters are async for the same reason — Clerk's user state lives on `@MainActor`.
protocol Authing: AnyObject, Sendable {
    var userId: String? { get async }
    var email: String? { get async }
    func sessionToken() async throws -> String
    func signOut() async
}

struct AuthTokenError: Error {
    let reason: String
}

/// Networking seam — same shape as URLSession.data(for:). Renamed from HTTPTransport to align with the constructor-injected style introduced when the BackendAPI singleton was removed.
protocol Transport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: Transport {}

/// Pure transport: builds requests, attaches auth, encodes JSON (snake_case), decodes responses. No feature methods — those live in `BackendEndpoints`. Used to be an `actor` with a singleton; now a constructor-injected `final class` so SwiftUI views and tests can hand in their own transport / auth. `Observable` lets it ride in `@Environment`.
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

    /// Backend uses snake_case JSON; Swift uses camelCase property names. Single encoder/decoder configured here is the only place this conversion lives.
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

    /// Allow caller paths to include a query string (e.g. `/stats/cefr?level=B1`). `URL.appendingPathComponent` would percent-encode the `?`, so route through `URLComponents` to keep the query intact.
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
