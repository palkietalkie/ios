import Foundation

/// Reports onboarding step views/completions to the backend drop-off feed (`/onboarding/announce`). A seam so OnboardingView is testable without a live backend; best-effort by design — a failure here must never block or slow the user.
protocol OnboardingAnnouncing: Sendable {
    /// Returns the Slack thread ts to thread later events under (the first call opens the thread). nil on any failure.
    func announce(step: String, phase: String, threadTs: String?) async -> String?
}

struct BackendOnboardingAnnouncer: OnboardingAnnouncing {
    let baseURL: URL
    let auth: any Authing
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

    func announce(step: String, phase: String, threadTs: String?) async -> String? {
        // Onboarding is post-sign-in, so there's always a session; without a token we simply skip (best-effort).
        guard let token = try? await auth.sessionToken() else { return nil }
        var request = URLRequest(url: baseURL.appendingPathComponent("onboarding/announce"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var payload: [String: String] = ["step": step, "phase": phase]
        if let threadTs { payload["thread_ts"] = threadTs }
        if let name = await auth.preferredName { payload["preferred_name"] = name }
        guard let body = try? JSONEncoder().encode(payload) else { return nil }
        request.httpBody = body
        guard let (data, _) = try? await send(request) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try? decoder.decode(OnboardingAnnounceResponse.self, from: data))?.threadTs
    }
}

private struct OnboardingAnnounceResponse: Decodable {
    let threadTs: String?
}

/// Default for tests/previews: does nothing, so hosting OnboardingView never touches the network. Production is wired in PalkieTalkieApp.
struct NoopOnboardingAnnouncer: OnboardingAnnouncing {
    func announce(step _: String, phase _: String, threadTs _: String?) async -> String? {
        nil
    }
}
