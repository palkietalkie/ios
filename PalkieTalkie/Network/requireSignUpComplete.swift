import ClerkKit

/// A Clerk sign-up creates a user + session ONLY when it reaches `.complete`. Every other terminal state (missing required fields, abandoned) leaves the user with no session — `verifyEmailCode` returns without throwing, yet there's nothing to sign the user in. This guard turns that silent dead-end into a real error so the user sees why and the founder's feed records the failure.
func requireSignUpComplete(status: SignUp.Status, missingFields: [SignUp.Field]) throws {
    guard status != .complete else { return }
    let fields = missingFields.map(\.rawValue).joined(separator: ", ")
    let detail = fields.isEmpty ? "status: \(status.rawValue)" : "missing: \(fields)"
    throw SignInServiceError.verificationIncomplete(
        "Couldn't finish creating your account (\(detail)). Email sign-up may need to be enabled in Clerk.",
    )
}
