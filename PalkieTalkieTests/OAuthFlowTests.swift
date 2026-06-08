import AuthenticationServices
import Foundation
@testable import PalkieTalkie
import UIKit
import XCTest

/// Drives the seamed OAuthFlow with a FakeWebAuthSessionFactory so the `start()` body — error → enum mapping, session.start() failure path, success path — actually runs under XCTest.
@MainActor
final class OAuthFlowTests: XCTestCase {
    // MARK: - Fake plumbing

    /// FakeSession invokes its `startBehavior` closure on `start()` and returns the staged Bool. Drives the OAuthFlow completion synchronously inside `start()`.
    private final class FakeSession: WebAuthSession {
        let startReturn: Bool
        let startBehavior: () -> Void
        init(startReturn: Bool, startBehavior: @escaping () -> Void) {
            self.startReturn = startReturn
            self.startBehavior = startBehavior
        }

        func start() -> Bool {
            startBehavior()
            return startReturn
        }
    }

    @MainActor
    private final class FakeFactory: WebAuthSessionFactory {
        var receivedURL: URL?
        var receivedScheme: String?
        /// Set BEFORE calling `flow.start(...)`. Invoked with the completion the OAuthFlow handed us; the closure decides whether to call completion(success) or completion(error).
        var driver: (((URL?, Error?) -> Void) -> Void)?
        /// What FakeSession.start() returns. False simulates ASWebAuthenticationSession refusing to launch.
        var sessionStartReturn = true

        func makeSession(
            url: URL,
            callbackURLScheme: String,
            presentationContextProvider _: ASWebAuthenticationPresentationContextProviding,
            completion: @escaping @Sendable (URL?, Error?) -> Void,
        ) -> WebAuthSession {
            receivedURL = url
            receivedScheme = callbackURLScheme
            let driver = self.driver
            return FakeSession(startReturn: sessionStartReturn) {
                driver?(completion)
            }
        }
    }

    // MARK: - Tests

    func testSuccessPathCompletesCleanly() async throws {
        let factory = FakeFactory()
        factory.driver = { completion in
            completion(URL(string: "palkietalkie://oauth/google?ok=1"), nil)
        }
        let flow = OAuthFlow(factory: factory)
        try await flow.start(authURL: XCTUnwrap(URL(string: "https://accounts.google.com/o/oauth2/v2/auth?x=1")))
        XCTAssertEqual(factory.receivedScheme, "palkietalkie")
        XCTAssertEqual(factory.receivedURL?.host, "accounts.google.com")
    }

    func testCancelledByUserMapsToOAuthErrorUserCancelled() async throws {
        let factory = FakeFactory()
        let cancelError = NSError(
            domain: ASWebAuthenticationSessionError.errorDomain,
            code: ASWebAuthenticationSessionError.canceledLogin.rawValue,
        )
        factory.driver = { completion in completion(nil, cancelError) }
        let flow = OAuthFlow(factory: factory)

        do {
            try await flow.start(authURL: XCTUnwrap(URL(string: "https://example.com/oauth")))
            XCTFail("expected throw")
        } catch OAuthError.userCancelled {
            // expected
        } catch {
            XCTFail("expected userCancelled, got \(error)")
        }
    }

    func testOtherErrorMapsToOAuthErrorSessionFailed() async throws {
        let factory = FakeFactory()
        let underlying = NSError(domain: "net", code: 503)
        factory.driver = { completion in completion(nil, underlying) }
        let flow = OAuthFlow(factory: factory)

        do {
            try await flow.start(authURL: XCTUnwrap(URL(string: "https://example.com/oauth")))
            XCTFail("expected throw")
        } catch let OAuthError.sessionFailed(inner) {
            XCTAssertEqual((inner as NSError).code, 503)
        } catch {
            XCTFail("expected sessionFailed, got \(error)")
        }
    }

    func testSessionStartFailureSurfaces() async throws {
        let factory = FakeFactory()
        factory.sessionStartReturn = false
        // No driver: session.start() returns false → flow throws session-failed.
        let flow = OAuthFlow(factory: factory)
        do {
            try await flow.start(authURL: XCTUnwrap(URL(string: "https://example.com")))
            XCTFail("expected throw")
        } catch let OAuthError.sessionFailed(inner) {
            XCTAssertEqual((inner as NSError).domain, "OAuthFlow")
        } catch {
            XCTFail("expected sessionFailed for start()=false, got \(error)")
        }
    }

    // MARK: - Static surface tests

    func testOAuthErrorCasesRoundTrip() {
        switch OAuthError.invalidURL {
        case .invalidURL: break
        default: XCTFail()
        }
        switch OAuthError.userCancelled {
        case .userCancelled: break
        default: XCTFail()
        }
        switch OAuthError.sessionFailed(URLError(.cancelled)) {
        case .sessionFailed: break
        default: XCTFail()
        }
    }

    func testSharedSingletonStable() {
        XCTAssertTrue(OAuthFlow.shared === OAuthFlow.shared)
    }

    /// `DefaultWebAuthSessionFactory.makeSession` constructs a real ASWebAuthenticationSession wrapped in RealWebAuthSession. Doesn't call start() — that would open the system auth sheet.
    func testDefaultFactoryConstructsSessionWithoutStarting() async throws {
        let factory = await DefaultWebAuthSessionFactory()
        _ = try await factory.makeSession(
            url: XCTUnwrap(URL(string: "https://example.test/auth")),
            callbackURLScheme: "palkietalkie",
            presentationContextProvider: OAuthFlow.shared,
            completion: { _, _ in },
        )
    }

    // presentationAnchorMainActor() is NOT covered by a test — XCTest's host app on iOS 26 simulator doesn't bring up a foreground-active UIWindowScene before tests run, and the function's last branch is a precondition failure on that path. Reachable only via the real ASWebAuthenticationSession callback in app runs, not a unit-testable surface.
}
