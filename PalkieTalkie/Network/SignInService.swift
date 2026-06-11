import Foundation

/// Seam over Clerk's sign-in actions (Apple / Google / email-code) so SignInView's logic is testable without a live Clerk context — same DI pattern as `Authing`/`ClerkAuthAdapter`. Production conformer: `ClerkSignInService`. Tests inject a fake.
@MainActor
protocol SignInService: AnyObject {
    func signInWithApple() async throws
    func signInWithGoogle() async throws
    /// Sends an email code via the SIGN-IN flow (existing account). Throws if no account exists for `email` — the caller falls back to `signUpWithEmailCode`. Remembers the pending sign-in internally; follow with `verifyEmailCode`.
    func signInWithEmailCode(_ email: String) async throws
    /// Creates an account for `email` and sends it a verification code (SIGN-UP flow). Used when `signInWithEmailCode` reports no existing account. Remembers the pending sign-up internally; follow with `verifyEmailCode`.
    func signUpWithEmailCode(_ email: String) async throws
    func verifyEmailCode(_ code: String) async throws
}

enum SignInServiceError: LocalizedError {
    case noPendingEmailSignIn
    /// The code was accepted but the flow didn't reach a completed session (e.g. Clerk still wants a password / name). Without this, the app silently bounces back to sign-in with no session and no explanation.
    case verificationIncomplete(String)

    var errorDescription: String? {
        switch self {
        case .noPendingEmailSignIn:
            "No email sign-in in progress. Request a new code."
        case let .verificationIncomplete(reason):
            reason
        }
    }
}
