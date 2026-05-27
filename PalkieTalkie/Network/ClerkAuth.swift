import ClerkKit
import Foundation

/// Thin wrapper around the Clerk SDK so the rest of the app doesn't depend on Clerk types directly. Everything is async
/// — Clerk's network calls are remote.
@MainActor
final class ClerkAuth {
    static let shared = ClerkAuth()

    var isSignedIn: Bool {
        Clerk.shared.user != nil
    }

    var currentUserId: String? {
        Clerk.shared.user?.id
    }

    var currentUserEmail: String? {
        Clerk.shared.user?.primaryEmailAddress?.emailAddress
    }

    /// Backend uses Clerk JWT as bearer token. Returns cached if not near expiry (Clerk default).
    /// Throws so callers can distinguish "no session" (real signed-out state) from "session present but Clerk's token
    /// refresh just failed" (transient — used to look identical to the UI as "not signed in").
    func sessionToken() async throws -> String {
        guard let session = Clerk.shared.session else {
            throw AuthTokenError(reason: "no Clerk session")
        }
        do {
            guard let token = try await session.getToken() else {
                throw AuthTokenError(reason: "Clerk returned nil token")
            }
            return token
        } catch let error as AuthTokenError {
            throw error
        } catch {
            throw AuthTokenError(reason: "Clerk getToken failed: \(error.localizedDescription)")
        }
    }

    func signOut() async {
        try? await Clerk.shared.auth.signOut()
    }
}
