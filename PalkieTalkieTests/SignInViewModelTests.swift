@testable import PalkieTalkie
import XCTest

/// Controllable `SignInService` for tests — records calls and can be told to throw on any path.
@MainActor
final class FakeSignInService: SignInService {
    private(set) var appleCalls = 0
    private(set) var googleCalls = 0
    private(set) var signInEmails: [String] = []
    private(set) var signUpEmails: [String] = []
    private(set) var verifiedCodes: [String] = []
    var throwOnApple = false
    var throwOnGoogle = false
    var throwOnSignIn = false
    var throwOnSignUp = false
    var throwOnVerify = false

    struct Boom: LocalizedError { var errorDescription: String? {
        "boom"
    } }

    func signInWithApple() async throws {
        appleCalls += 1
        if throwOnApple { throw Boom() }
    }

    func signInWithGoogle() async throws {
        googleCalls += 1
        if throwOnGoogle { throw Boom() }
    }

    func signInWithEmailCode(_ email: String) async throws {
        signInEmails.append(email)
        if throwOnSignIn { throw Boom() }
    }

    func signUpWithEmailCode(_ email: String) async throws {
        signUpEmails.append(email)
        if throwOnSignUp { throw Boom() }
    }

    func verifyEmailCode(_ code: String) async throws {
        verifiedCodes.append(code)
        if throwOnVerify { throw Boom() }
    }
}

/// Records `announce` events so tests can assert the founder's Slack feed fires on every auth path — success AND failure — with the right method and threading. Returns a fixed parent `ts` so the email send→verify thread can be checked.
@MainActor
final class FakeAuthAnnouncer: AuthAnnouncing {
    private(set) var events: [AuthEvent] = []
    var returnTs: String? = "parent.ts"

    func announce(_ event: AuthEvent) async -> String? {
        events.append(event)
        return returnTs
    }
}

/// End-to-end behavior of all three sign-in paths (Apple, Google, email code) through the SignInService seam. Pre-seam, none of these paths had a success-path test and the email path had no interaction test at all.
@MainActor
final class SignInViewModelTests: XCTestCase {
    // MARK: Apple

    func testAppleSuccessCallsServiceNoError() async {
        let svc = FakeSignInService()
        let vm = SignInViewModel(service: svc, announcer: FakeAuthAnnouncer())
        await vm.signInWithApple()
        XCTAssertEqual(svc.appleCalls, 1)
        XCTAssertNil(vm.status)
        XCTAssertFalse(vm.inProgress)
    }

    func testAppleFailureSetsStatus() async {
        let svc = FakeSignInService()
        svc.throwOnApple = true
        let vm = SignInViewModel(service: svc, announcer: FakeAuthAnnouncer())
        await vm.signInWithApple()
        XCTAssertEqual(svc.appleCalls, 1)
        XCTAssertNotNil(vm.status)
        XCTAssertFalse(vm.inProgress)
    }

    // MARK: Google

    func testGoogleSuccessCallsServiceNoError() async {
        let svc = FakeSignInService()
        let vm = SignInViewModel(service: svc, announcer: FakeAuthAnnouncer())
        await vm.signInWithGoogle()
        XCTAssertEqual(svc.googleCalls, 1)
        XCTAssertNil(vm.status)
    }

    func testGoogleFailureSetsStatus() async {
        let svc = FakeSignInService()
        svc.throwOnGoogle = true
        let vm = SignInViewModel(service: svc, announcer: FakeAuthAnnouncer())
        await vm.signInWithGoogle()
        XCTAssertNotNil(vm.status)
    }

    // MARK: Email — send

    func testSendEmailCodeSuccessSwitchesToCodeEntry() async {
        let svc = FakeSignInService()
        let vm = SignInViewModel(service: svc, announcer: FakeAuthAnnouncer())
        vm.email = "wes@example.com"
        await vm.sendEmailCode()
        XCTAssertEqual(svc.signInEmails, ["wes@example.com"])
        XCTAssertEqual(svc.signUpEmails, [], "an existing-account sign-in must not also create a sign-up")
        XCTAssertTrue(vm.awaitingCode)
        XCTAssertEqual(vm.status, "Code sent. Check your email.")
    }

    /// Bug: iOS email autofill appends a trailing space, which Clerk rejects as invalid. The view-model must trim it.
    func testSendEmailCodeTrimsAutofillWhitespace() async {
        let svc = FakeSignInService()
        let vm = SignInViewModel(service: svc, announcer: FakeAuthAnnouncer())
        vm.email = "wes@gitauto.ai "
        await vm.sendEmailCode()
        XCTAssertEqual(
            svc.signInEmails,
            ["wes@gitauto.ai"],
            "trailing whitespace from autofill must be trimmed before sending",
        )
        XCTAssertEqual(vm.email, "wes@gitauto.ai", "the field should reflect the trimmed value")
        XCTAssertTrue(vm.awaitingCode)
    }

    func testSendEmailCodeWhitespaceOnlyDoesNotCallService() async {
        let svc = FakeSignInService()
        let vm = SignInViewModel(service: svc, announcer: FakeAuthAnnouncer())
        vm.email = "   "
        await vm.sendEmailCode()
        XCTAssertEqual(svc.signInEmails, [])
        XCTAssertEqual(svc.signUpEmails, [])
        XCTAssertFalse(vm.awaitingCode)
        XCTAssertNotNil(vm.status)
    }

    /// Bug: a first-time user has no account, so sign-in fails with "couldn't find your account". The view-model must fall back to sign-up so they can register — otherwise nobody can ever create an account.
    func testSendEmailCodeNewUserFallsBackToSignUp() async {
        let svc = FakeSignInService()
        svc.throwOnSignIn = true // no existing account
        let vm = SignInViewModel(service: svc, announcer: FakeAuthAnnouncer())
        vm.email = "newuser@example.com"
        await vm.sendEmailCode()
        XCTAssertEqual(svc.signInEmails, ["newuser@example.com"], "should try sign-in first")
        XCTAssertEqual(svc.signUpEmails, ["newuser@example.com"], "then fall back to sign-up for the new account")
        XCTAssertTrue(vm.awaitingCode, "a new user must reach code entry, not a dead-end error")
        XCTAssertEqual(vm.status, "Code sent. Check your email.")
    }

    func testSendEmailCodeFailureStaysOnEmailEntry() async {
        let svc = FakeSignInService()
        svc.throwOnSignIn = true
        svc.throwOnSignUp = true // both paths fail (e.g. network down)
        let vm = SignInViewModel(service: svc, announcer: FakeAuthAnnouncer())
        vm.email = "wes@example.com"
        await vm.sendEmailCode()
        XCTAssertFalse(vm.awaitingCode, "a failed send must not advance to code entry")
        XCTAssertNotNil(vm.status)
    }

    // MARK: Email — verify

    func testVerifyEmailCodeSuccessClearsState() async {
        let svc = FakeSignInService()
        let vm = SignInViewModel(service: svc, announcer: FakeAuthAnnouncer())
        vm.awaitingCode = true
        vm.code = "123456"
        await vm.verifyEmailCode()
        XCTAssertEqual(svc.verifiedCodes, ["123456"])
        XCTAssertFalse(vm.awaitingCode)
        XCTAssertEqual(vm.code, "")
    }

    func testVerifyEmailCodeFailureKeepsCodeEntryAndSetsStatus() async {
        let svc = FakeSignInService()
        svc.throwOnVerify = true
        let vm = SignInViewModel(service: svc, announcer: FakeAuthAnnouncer())
        vm.awaitingCode = true
        vm.code = "000000"
        await vm.verifyEmailCode()
        XCTAssertTrue(vm.awaitingCode, "a failed verify must keep the user on code entry")
        XCTAssertNotNil(vm.status)
    }

    // MARK: Slack announce feed

    func testAppleSuccessAnnouncesAppleMethod() async {
        let ann = FakeAuthAnnouncer()
        let vm = SignInViewModel(service: FakeSignInService(), announcer: ann)
        await vm.signInWithApple()
        XCTAssertEqual(ann.events, [.succeeded(method: "Apple", threadTs: nil)])
    }

    /// A failed sign-in MUST ping the feed too — a silent failure hides a broken funnel.
    func testAppleFailureAnnouncesFailure() async {
        let svc = FakeSignInService()
        svc.throwOnApple = true
        let ann = FakeAuthAnnouncer()
        let vm = SignInViewModel(service: svc, announcer: ann)
        await vm.signInWithApple()
        XCTAssertEqual(
            ann.events,
            [.failed(method: "Apple", reason: diagnoseAuthError(FakeSignInService.Boom()), email: nil, threadTs: nil)],
        )
    }

    func testGoogleSuccessAnnouncesGoogleMethod() async {
        let ann = FakeAuthAnnouncer()
        let vm = SignInViewModel(service: FakeSignInService(), announcer: ann)
        await vm.signInWithGoogle()
        XCTAssertEqual(ann.events, [.succeeded(method: "Google", threadTs: nil)])
    }

    func testGoogleFailureAnnouncesFailure() async {
        let svc = FakeSignInService()
        svc.throwOnGoogle = true
        let ann = FakeAuthAnnouncer()
        let vm = SignInViewModel(service: svc, announcer: ann)
        await vm.signInWithGoogle()
        XCTAssertEqual(
            ann.events,
            [.failed(method: "Google", reason: diagnoseAuthError(FakeSignInService.Boom()), email: nil, threadTs: nil)],
        )
    }

    /// The email flow announces twice: a pre-auth parent (carrying the typed address) on send, then a success reply threaded under the returned parent ts on verify — so the two land as one Slack thread.
    func testEmailSendThenVerifyAnnouncesInOneThread() async {
        let ann = FakeAuthAnnouncer()
        let vm = SignInViewModel(service: FakeSignInService(), announcer: ann)
        vm.email = "wes@gitauto.ai"
        await vm.sendEmailCode()
        vm.code = "123456"
        await vm.verifyEmailCode()
        XCTAssertEqual(ann.events, [
            .emailCodeRequested(email: "wes@gitauto.ai"),
            .succeeded(method: "Email", threadTs: "parent.ts"),
        ])
    }

    /// Bug repro: a valid code that doesn't complete the sign-up (Clerk `missing_requirements`) used to silently bounce the user back to sign-in. Now the service throws, so verify must surface the error AND report the failure threaded under the parent.
    func testEmailVerifyFailureAnnouncesFailureInThread() async {
        let svc = FakeSignInService()
        let ann = FakeAuthAnnouncer()
        let vm = SignInViewModel(service: svc, announcer: ann)
        vm.email = "newuser@example.com"
        await vm.sendEmailCode()
        svc.throwOnVerify = true
        vm.code = "123456"
        await vm.verifyEmailCode()
        XCTAssertTrue(vm.awaitingCode, "a failed verify must keep the user on code entry, not bounce them out")
        XCTAssertEqual(ann.events, [
            .emailCodeRequested(email: "newuser@example.com"),
            .failed(
                method: "Email",
                reason: diagnoseAuthError(FakeSignInService.Boom()),
                email: "newuser@example.com",
                threadTs: "parent.ts",
            ),
        ])
    }

    func testEmailSendFailureAnnouncesFailure() async {
        let svc = FakeSignInService()
        svc.throwOnSignIn = true
        svc.throwOnSignUp = true
        let ann = FakeAuthAnnouncer()
        let vm = SignInViewModel(service: svc, announcer: ann)
        vm.email = "wes@gitauto.ai"
        await vm.sendEmailCode()
        XCTAssertEqual(
            ann.events,
            [.failed(
                method: "Email",
                reason: diagnoseAuthError(FakeSignInService.Boom()),
                email: "wes@gitauto.ai",
                threadTs: nil,
            )],
        )
    }
}
