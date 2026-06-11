import ClerkKit
import Foundation
@testable import PalkieTalkie
import XCTest

/// Builds a `SignUp` in a chosen terminal state. Only `.complete` carries a session; `.missingRequirements` is the real bug (e.g. Clerk still wants a password).
@MainActor
private func makeSignUp(_ status: SignUp.Status, missingFields: [SignUp.Field] = []) -> SignUp {
    SignUp(
        id: "su_test",
        status: status,
        requiredFields: [],
        optionalFields: [],
        missingFields: missingFields,
        unverifiedFields: [],
        verifications: [:],
        passwordEnabled: false,
        abandonAt: Date(),
    )
}

@MainActor
private func makeSignIn(_ status: SignIn.Status) -> SignIn {
    SignIn(id: "si_test", status: status)
}

private struct Boom: LocalizedError {
    var errorDescription: String? {
        "boom"
    }
}

/// Fake Clerk SDK boundary so the REAL `ClerkSignInService` logic runs against controllable results. Each leg is a `Result` (or thrown error) the test sets.
@MainActor
private final class FakeClerkAuthGateway: ClerkAuthGateway {
    var appleError: Error?
    var googleError: Error?
    var startSignInResult: Result<SignIn, Error> = .success(makeSignIn(.needsFirstFactor))
    var startSignUpResult: Result<SignUp, Error> = .success(makeSignUp(.missingRequirements))
    var verifySignInResult: Result<SignIn, Error> = .success(makeSignIn(.complete))
    var verifySignUpResult: Result<SignUp, Error> = .success(makeSignUp(.complete))

    private(set) var appleCalls = 0
    private(set) var googleCalls = 0
    private(set) var startedSignInEmails: [String] = []
    private(set) var startedSignUpEmails: [String] = []

    func signInWithApple() async throws {
        appleCalls += 1
        if let appleError { throw appleError }
    }

    func signInWithGoogle() async throws {
        googleCalls += 1
        if let googleError { throw googleError }
    }

    func startEmailSignIn(_ email: String) async throws -> SignIn {
        startedSignInEmails.append(email)
        return try startSignInResult.get()
    }

    func startEmailSignUp(_ email: String) async throws -> SignUp {
        startedSignUpEmails.append(email)
        return try startSignUpResult.get()
    }

    func verify(signIn _: SignIn, code _: String) async throws -> SignIn {
        try verifySignInResult.get()
    }

    func verify(signUp _: SignUp, code _: String) async throws -> SignUp {
        try verifySignUpResult.get()
    }
}

/// Drives the production `ClerkSignInService` through all six auth patterns (Apple / Google / email × sign-in / sign-up), success and failure, with only the irreducible Clerk SDK boundary faked. This is the layer the earlier suite skipped — the email verify→status-guard glue that shipped broken lives here, not in the view-model.
///
/// Not covered (and not coverable headlessly): the Clerk network itself and the Apple/Google OS auth sheets, which `signInWith{Apple,Google}` present below this seam. Those need a real device sign-in (manual or XCUITest with live credentials).
@MainActor
final class ClerkSignInServiceTests: XCTestCase {
    // MARK: Apple

    //
    // Why there is NO live e2e for Apple/Google (only these logic tests), while email HAS one (`ClerkEmailAuthE2ETests`):
    //
    // `Clerk.shared.auth.signInWithApple()` calls `SignInWithAppleHelper.getAppleIdCredential`, which presents Apple's native `ASAuthorizationController` system sheet; the Google path opens an `ASWebAuthenticationSession` web flow. Both are OUT-OF-PROCESS system UIs that require a human to tap and a real Apple/Google account to sign in. XCTest runs in-process and cannot drive them. The SDK exposes no hook to inject a fake credential — `signUpWithIdToken` only accepts a *real* OAuth id-token, which can't be minted in a test without real credentials.
    //
    // Email is different: it's pure API (request code → submit code), so its whole chain is automatable against the live dev instance (see ClerkEmailAuthE2ETests). For Apple/Google the only real e2e is a human tapping through on a device, so we cover our own code here (the gateway delegation + success/failure propagation) and verify the system-sheet step by hand on device.

    func testAppleSuccess() async throws {
        let gw = FakeClerkAuthGateway()
        try await ClerkSignInService(gateway: gw).signInWithApple()
        XCTAssertEqual(gw.appleCalls, 1)
    }

    func testAppleFailurePropagates() async {
        let gw = FakeClerkAuthGateway()
        gw.appleError = Boom()
        let svc = ClerkSignInService(gateway: gw)
        do {
            try await svc.signInWithApple()
            XCTFail("expected an error")
        } catch {
            // expected
        }
    }

    // MARK: Google

    func testGoogleSuccess() async throws {
        let gw = FakeClerkAuthGateway()
        try await ClerkSignInService(gateway: gw).signInWithGoogle()
        XCTAssertEqual(gw.googleCalls, 1)
    }

    func testGoogleFailurePropagates() async {
        let gw = FakeClerkAuthGateway()
        gw.googleError = Boom()
        let svc = ClerkSignInService(gateway: gw)
        do {
            try await svc.signInWithGoogle()
            XCTFail("expected an error")
        } catch {
            // expected
        }
    }

    // MARK: Email sign-in (existing account)

    func testEmailSignInSuccess() async throws {
        let gw = FakeClerkAuthGateway()
        gw.verifySignInResult = .success(makeSignIn(.complete))
        let svc = ClerkSignInService(gateway: gw)
        try await svc.signInWithEmailCode("a@b.com")
        try await svc.verifyEmailCode("123456")
        XCTAssertEqual(gw.startedSignInEmails, ["a@b.com"])
    }

    func testEmailSignInBadCodeThrows() async throws {
        let gw = FakeClerkAuthGateway()
        gw.verifySignInResult = .failure(Boom())
        let svc = ClerkSignInService(gateway: gw)
        try await svc.signInWithEmailCode("a@b.com")
        do {
            try await svc.verifyEmailCode("000000")
            XCTFail("expected an error")
        } catch {
            // expected
        }
    }

    /// A code accepted but the sign-in not `.complete` (e.g. second factor) must surface as an error, not a silent no-session success.
    func testEmailSignInIncompleteThrows() async throws {
        let gw = FakeClerkAuthGateway()
        gw.verifySignInResult = .success(makeSignIn(.needsSecondFactor))
        let svc = ClerkSignInService(gateway: gw)
        try await svc.signInWithEmailCode("a@b.com")
        do {
            try await svc.verifyEmailCode("123456")
            XCTFail("expected an error")
        } catch {
            guard case SignInServiceError.verificationIncomplete = error else {
                return XCTFail("expected .verificationIncomplete, got \(error)")
            }
        }
    }

    func testVerifyWithoutPendingThrows() async {
        let svc = ClerkSignInService(gateway: FakeClerkAuthGateway())
        do {
            try await svc.verifyEmailCode("123456")
            XCTFail("expected an error")
        } catch {
            guard case SignInServiceError.noPendingEmailSignIn = error else {
                return XCTFail("expected .noPendingEmailSignIn, got \(error)")
            }
        }
    }

    // MARK: Email sign-up (new account)

    func testEmailSignUpSuccess() async throws {
        let gw = FakeClerkAuthGateway()
        gw.verifySignUpResult = .success(makeSignUp(.complete))
        let svc = ClerkSignInService(gateway: gw)
        try await svc.signUpWithEmailCode("new@b.com")
        try await svc.verifyEmailCode("123456")
        XCTAssertEqual(gw.startedSignUpEmails, ["new@b.com"])
    }

    /// THE shipped bug: a valid code whose sign-up is `missing_requirements` (no password) created no session, yet the old code reported success and the app bounced back to sign-in. Now it must throw.
    func testEmailSignUpMissingRequirementsThrows() async throws {
        let gw = FakeClerkAuthGateway()
        gw.verifySignUpResult = .success(makeSignUp(.missingRequirements, missingFields: [.password]))
        let svc = ClerkSignInService(gateway: gw)
        try await svc.signUpWithEmailCode("new@b.com")
        do {
            try await svc.verifyEmailCode("123456")
            XCTFail("expected an error")
        } catch {
            guard case SignInServiceError.verificationIncomplete = error else {
                return XCTFail("expected .verificationIncomplete, got \(error)")
            }
        }
    }

    func testEmailSignUpBadCodeThrows() async throws {
        let gw = FakeClerkAuthGateway()
        gw.verifySignUpResult = .failure(Boom())
        let svc = ClerkSignInService(gateway: gw)
        try await svc.signUpWithEmailCode("new@b.com")
        do {
            try await svc.verifyEmailCode("000000")
            XCTFail("expected an error")
        } catch {
            // expected
        }
    }

    /// After a sign-up is started, verify must take the sign-UP branch even if a stale sign-in was pending — `signUpWithEmailCode` clears it. Pinned by making the sign-in verify path fail: if it were taken, this would throw.
    func testSignUpTakesPrecedenceOverStaleSignIn() async throws {
        let gw = FakeClerkAuthGateway()
        gw.verifySignInResult = .failure(Boom())
        gw.verifySignUpResult = .success(makeSignUp(.complete))
        let svc = ClerkSignInService(gateway: gw)
        try await svc.signInWithEmailCode("a@b.com")
        try await svc.signUpWithEmailCode("a@b.com")
        try await svc.verifyEmailCode("123456")
    }
}
