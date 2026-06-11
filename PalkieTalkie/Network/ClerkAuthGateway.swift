import ClerkKit

/// The irreducible boundary over Clerk's SDK: the six raw operations `ClerkSignInService` needs, each a thin passthrough to `Clerk.shared.auth`. Splitting this out is what makes `ClerkSignInService`'s real logic — the email sign-in→sign-up fallback's pending state and the completion guards — testable against canned `SignIn`/`SignUp` values. Everything below this seam (Clerk's network, Apple/Google's OS sheets) can only be exercised on a real device, so it's kept logic-free.
@MainActor
protocol ClerkAuthGateway: Sendable {
    func signInWithApple() async throws
    func signInWithGoogle() async throws
    func startEmailSignIn(_ email: String) async throws -> SignIn
    func startEmailSignUp(_ email: String) async throws -> SignUp
    func verify(signIn: SignIn, code: String) async throws -> SignIn
    func verify(signUp: SignUp, code: String) async throws -> SignUp
}

struct LiveClerkAuthGateway: ClerkAuthGateway {
    func signInWithApple() async throws {
        _ = try await Clerk.shared.auth.signInWithApple()
    }

    func signInWithGoogle() async throws {
        _ = try await Clerk.shared.auth.signInWithOAuth(provider: .google)
    }

    func startEmailSignIn(_ email: String) async throws -> SignIn {
        try await Clerk.shared.auth.signInWithEmailCode(emailAddress: email)
    }

    func startEmailSignUp(_ email: String) async throws -> SignUp {
        // Clerk's email-code sign-in doesn't auto-transfer to sign-up the way OAuth does, so a first-time user must be created explicitly: create the SignUp, then send the code from it.
        let signUp = try await Clerk.shared.auth.signUp(emailAddress: email)
        return try await signUp.sendEmailCode()
    }

    func verify(signIn: SignIn, code: String) async throws -> SignIn {
        try await signIn.verifyCode(code)
    }

    func verify(signUp: SignUp, code: String) async throws -> SignUp {
        try await signUp.verifyEmailCode(code)
    }
}
