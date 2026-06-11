import ClerkKit
import Foundation

/// Production `SignInService`. Owns the real flow logic — the pending email `SignIn`/`SignUp` held between send and verify, and the completion guards that catch a "code accepted but no session created" sign-up — while delegating the raw Clerk SDK calls to an injectable `ClerkAuthGateway` so that logic is unit-testable without a live Clerk context.
@MainActor
final class ClerkSignInService: SignInService {
    private let gateway: any ClerkAuthGateway
    private var pendingEmailSignIn: SignIn?
    private var pendingEmailSignUp: SignUp?

    init(gateway: any ClerkAuthGateway = LiveClerkAuthGateway()) {
        self.gateway = gateway
    }

    func signInWithApple() async throws {
        try await gateway.signInWithApple()
    }

    func signInWithGoogle() async throws {
        try await gateway.signInWithGoogle()
    }

    func signInWithEmailCode(_ email: String) async throws {
        pendingEmailSignIn = try await gateway.startEmailSignIn(email)
        pendingEmailSignUp = nil
    }

    func signUpWithEmailCode(_ email: String) async throws {
        pendingEmailSignUp = try await gateway.startEmailSignUp(email)
        pendingEmailSignIn = nil
    }

    func verifyEmailCode(_ code: String) async throws {
        if let signUp = pendingEmailSignUp {
            let result = try await gateway.verify(signUp: signUp, code: code)
            // A valid code with an incomplete sign-up returns without throwing but creates NO session — guard so the user isn't silently bounced back to the sign-in screen.
            try requireSignUpComplete(status: result.status, missingFields: result.missingFields)
            pendingEmailSignUp = nil
            return
        }
        guard let pending = pendingEmailSignIn else { throw SignInServiceError.noPendingEmailSignIn }
        let result = try await gateway.verify(signIn: pending, code: code)
        try requireSignInComplete(status: result.status)
        pendingEmailSignIn = nil
    }
}
