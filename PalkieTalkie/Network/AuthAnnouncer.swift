import Foundation

/// What happened on an auth attempt, reported to the backend so it can Slack the founder's feed. The auth method (which button) and outcome are only known on the client; the backend decides sign-in vs sign-up and formats the message.
enum AuthEvent: Equatable {
    /// Pre-auth: the user asked for an email code (no account/JWT yet). Posts the Slack thread parent; its `ts` is returned so the later success/failure replies thread under it.
    case emailCodeRequested(email: String)
    /// The user is now authenticated. `threadTs` set for the email flow so it replies under the "code requested" parent.
    case succeeded(method: String, threadTs: String?)
    /// The attempt failed (bad code, no session, OAuth cancelled, network). We notify on failure too — silent failures hide a broken funnel. `email` labels the user when known; `threadTs` threads an email-flow failure under its parent.
    case failed(method: String, reason: String, email: String?, threadTs: String?)
}

/// Reports an `AuthEvent` to the backend. A seam so SignInViewModel is testable without a live backend, and best-effort by design — a failure here must never block the user.
protocol AuthAnnouncing: Sendable {
    func announce(_ event: AuthEvent) async -> String?
}

struct BackendAuthAnnouncer: AuthAnnouncing {
    let baseURL: URL
    let auth: any Authing
    /// Injected so tests can stub the network without a live backend; production passes URLSession.shared.
    let send: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(
        baseURL: URL,
        auth: any Authing,
        send: @escaping @Sendable (URLRequest) async throws
            -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) },
    ) {
        self.baseURL = baseURL
        self.auth = auth
        self.send = send
    }

    func announce(_ event: AuthEvent) async -> String? {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/announce"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: String] = [:]
        switch event {
        case let .emailCodeRequested(email):
            payload = ["method": "Email", "outcome": "requested", "pending_email": email]
        case let .succeeded(method, threadTs):
            // Only a success has a session, so only a success carries the JWT the backend needs to identify the user and decide in vs up.
            guard let token = try? await auth.sessionToken() else { return nil }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            payload = ["method": method, "outcome": "succeeded"]
            // Name + email so the feed reads "Wes Nishio (wes@…)" instead of an opaque user_… id. The JWT often lacks these claims, so iOS sends what Clerk holds.
            if let name = await auth.preferredName { payload["preferred_name"] = name }
            if let mail = await auth.email { payload["email"] = mail }
            if let threadTs { payload["thread_ts"] = threadTs }
        case let .failed(method, reason, email, threadTs):
            payload = ["method": method, "outcome": "failed", "reason": reason]
            if let email { payload["pending_email"] = email }
            if let threadTs { payload["thread_ts"] = threadTs }
        }

        guard let body = try? JSONEncoder().encode(payload) else { return nil }
        request.httpBody = body
        guard let (data, _) = try? await send(request) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try? decoder.decode(AnnounceResponse.self, from: data))?.threadTs
    }
}

private struct AnnounceResponse: Decodable {
    let threadTs: String?
}
