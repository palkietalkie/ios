import Foundation
import Observation

/// View-model for `SignInView`. Owns the form state plus the three sign-in flows (Apple, Google, email code) behind a `SignInService` seam so every path is unit-testable without a live Clerk context.
@MainActor
@Observable
final class SignInViewModel {
    var email = ""
    var code = ""
    /// True once a code has been sent — the view swaps the email field for the code field.
    var awaitingCode = false
    var status: String?
    var inProgress = false

    private let service: any SignInService
    private let announcer: any AuthAnnouncing
    /// Slack thread parent captured when the email code is sent, so the verify notification replies under it (one thread per email sign-in).
    private var emailThreadTs: String?

    init(
        service: any SignInService = ClerkSignInService(),
        announcer: any AuthAnnouncing = AppEnvironment.makeProductionAnnouncer(),
    ) {
        self.service = service
        self.announcer = announcer
    }

    func signInWithApple() async {
        inProgress = true
        defer { inProgress = false }
        do {
            try await service.signInWithApple()
            _ = await announcer.announce(.succeeded(method: "Apple", threadTs: nil))
        } catch {
            // Backing out of the Apple sheet isn't a failure — clear any message and don't alert the feed.
            guard !isUserCancellation(error) else { status = nil; return }
            status = "Apple sign-in failed: \(error.localizedDescription)"
            _ = await announcer.announce(.failed(
                method: "Apple",
                reason: diagnoseAuthError(error),
                email: nil,
                threadTs: nil,
            ))
        }
    }

    func signInWithGoogle() async {
        inProgress = true
        defer { inProgress = false }
        do {
            try await service.signInWithGoogle()
            _ = await announcer.announce(.succeeded(method: "Google", threadTs: nil))
        } catch {
            // Dismissing the Google web sheet (canceledLogin) isn't a failure — no error, no alert.
            guard !isUserCancellation(error) else { status = nil; return }
            status = "Google sign-in failed: \(error.localizedDescription)"
            _ = await announcer.announce(.failed(
                method: "Google",
                reason: diagnoseAuthError(error),
                email: nil,
                threadTs: nil,
            ))
        }
    }

    func sendEmailCode() async {
        // iOS email autofill (tapping a suggestion) appends a trailing space, which Clerk rejects as an invalid address. Trim before sending so the user isn't blocked by an invisible character.
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        email = trimmed
        guard !trimmed.isEmpty else {
            status = "Enter your email address."
            return
        }
        // Reject autofill junk ("Sign in with Apple", "Hide My Email") before it round-trips to Clerk and fires a failure alert — an instant inline hint is better UX and keeps the feed clean.
        guard isValidEmailFormat(trimmed) else {
            status = "Enter a valid email address."
            return
        }
        inProgress = true
        defer { inProgress = false }
        do {
            try await service.signInWithEmailCode(trimmed)
            awaitingCode = true
            status = "Code sent. Check your email."
            emailThreadTs = await announcer.announce(.emailCodeRequested(email: trimmed))
        } catch {
            // No existing account → create one and send the code from the sign-up flow. Without this fallback a first-time user is stuck on "couldn't find your account" and can never register.
            do {
                try await service.signUpWithEmailCode(trimmed)
                awaitingCode = true
                status = "Code sent. Check your email."
                emailThreadTs = await announcer.announce(.emailCodeRequested(email: trimmed))
            } catch {
                status = "Couldn't send code: \(error.localizedDescription)"
                _ = await announcer.announce(.failed(
                    method: "Email",
                    reason: diagnoseAuthError(error),
                    email: trimmed,
                    threadTs: nil,
                ))
            }
        }
    }

    func verifyEmailCode() async {
        inProgress = true
        defer { inProgress = false }
        do {
            try await service.verifyEmailCode(code)
            awaitingCode = false
            code = ""
            // Authenticated now → reply "signed in/up with Email" under the "code requested" thread parent.
            _ = await announcer.announce(.succeeded(method: "Email", threadTs: emailThreadTs))
            emailThreadTs = nil
        } catch {
            // Keep the user on code entry (emailThreadTs intact) so a retry threads correctly, and tell the founder's feed it failed.
            status = "Verification failed: \(error.localizedDescription)"
            _ = await announcer.announce(.failed(
                method: "Email",
                reason: diagnoseAuthError(error),
                email: email,
                threadTs: emailThreadTs,
            ))
        }
    }
}
