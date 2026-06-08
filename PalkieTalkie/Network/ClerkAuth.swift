import ClerkKit
import Foundation

/// Production conformer for `Authing`. Wraps the Clerk SDK so the rest of the app doesn't depend on Clerk types
/// directly. All public methods are async and hop to MainActor internally because Clerk's user / session state lives
/// on the main actor.
///
/// Used to be `ClerkAuth` (a `@MainActor` final class with a `static let shared` accessor); singleton was removed in
/// favor of constructor injection via `@Environment(\.authing, …)`. Tests now hand in a `StubAuthing` instead of
/// touching Clerk at all.
final class ClerkAuthAdapter: Authing, @unchecked Sendable {
    init() {}

    var userId: String? {
        get async {
            await MainActor.run { Clerk.shared.user?.id }
        }
    }

    var email: String? {
        get async {
            await MainActor.run { Clerk.shared.user?.primaryEmailAddress?.emailAddress }
        }
    }

    /// Backend uses Clerk JWT as bearer token. Returns cached if not near expiry (Clerk default).
    /// Throws so callers can distinguish "no session" (real signed-out state) from "session present but Clerk's token
    /// refresh just failed" (transient — used to look identical to the UI as "not signed in").
    func sessionToken() async throws -> String {
        let session = await MainActor.run { Clerk.shared.session }
        guard let session else {
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
        await MainActor.run {
            Task { try? await Clerk.shared.auth.signOut() }
        }
    }
}
