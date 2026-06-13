import ClerkKit

/// Mirror of `requireSignUpComplete` for the sign-in side: a session exists only at `.complete`. Any `needs*` status (second factor, new password, …) means the code was accepted but the user is NOT signed in — surface it instead of pretending success and bouncing to the sign-in screen.
func requireSignInComplete(status: SignIn.Status) throws {
    guard status != .complete else { return }
    throw SignInServiceError.verificationIncomplete(
        "Sign-in didn't complete (status: \(status.rawValue)). Request a new code and try again.",
    )
}
