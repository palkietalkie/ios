import Foundation

/// Injectable seam over `OAuthFlow.shared.start(authURL:)`. Production wires the real OAuthFlow; tests inject a fake that throws canned OAuthError values so the IntegrationsView catch branches can run without the system browser sheet.
protocol OAuthStarting: Sendable {
    func start(authURL: URL) async throws
}

@MainActor
struct DefaultOAuthStarter: OAuthStarting {
    func start(authURL: URL) async throws {
        try await OAuthFlow.shared.start(authURL: authURL)
    }
}
