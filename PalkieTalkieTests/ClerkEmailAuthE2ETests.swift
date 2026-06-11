import ClerkKit
@testable import PalkieTalkie
import XCTest

/// TRUE end-to-end for the EMAIL auth flows against the live **dev** Clerk instance over the network — no fakes. Drives the real `ClerkSignInService` → `LiveClerkAuthGateway` → `Clerk.shared.auth`, using a Clerk dev test email (`+clerk_test`, no real inbox) and the dev test code `424242`. Covers both directions: a brand-new email (sign-UP creates the account + a session) and the same email again (sign-IN returns a session). Native bot protection is the device-token handshake ClerkKit does automatically — no CAPTCHA UI — so the only requirement beyond the network is a keychain, which is why this must run SIGNED (not `CODE_SIGNING_ALLOWED=NO`).
///
/// Apple/Google are deliberately NOT here: their SDK entrypoints present the system Apple ID sheet / web auth session, which automated XCTest cannot drive. Those flows are covered at the logic level by `ClerkSignInServiceTests` and verified by hand on device.
///
/// Gated behind `RUN_CLERK_E2E=1` so the fast unit suite and offline CI skip it. Run signed:
///   TEST_RUNNER_RUN_CLERK_E2E=1 xcodebuild ... -allowProvisioningUpdates test   (no CODE_SIGNING_ALLOWED=NO)
final class ClerkEmailAuthE2ETests: XCTestCase {
    private static let devPublishableKey = "pk_test_Y3V0ZS10aWNrLTQxLmNsZXJrLmFjY291bnRzLmRldiQ"

    @MainActor
    func testEmailSignUpThenSignInCreatesSession() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_CLERK_E2E"] == "1",
            "Live Clerk e2e — set RUN_CLERK_E2E=1 and run signed (needs keychain + network).",
        )

        _ = Clerk.configure(publishableKey: Self.devPublishableKey)
        _ = try await Clerk.shared.refreshEnvironment()
        _ = try? await Clerk.shared.refreshClient()

        let email = "wes_e2e_\(UInt64.random(in: 0 ..< .max))+clerk_test@gitauto.ai"
        let service = ClerkSignInService()

        // Sign-UP: a brand-new email fails sign-in, then falls back to sign-up (mirrors SignInViewModel).
        do {
            try await service.signInWithEmailCode(email)
        } catch {
            try await service.signUpWithEmailCode(email)
        }
        try await service.verifyEmailCode("424242")
        XCTAssertNotNil(
            Clerk.shared.session,
            "passwordless sign-up must create a session; nil means the dev instance still requires a password",
        )
        try? await Clerk.shared.auth.signOut()

        // Sign-IN: the same email now exists, so sign-in succeeds directly.
        try await service.signInWithEmailCode(email)
        try await service.verifyEmailCode("424242")
        XCTAssertNotNil(Clerk.shared.session, "sign-in with an existing account must create a session")
        try? await Clerk.shared.auth.signOut()
    }
}
