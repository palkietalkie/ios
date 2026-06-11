import ClerkKit
import Foundation
@testable import PalkieTalkie
import XCTest

@MainActor
private func makeSignIn(_ status: SignIn.Status) -> SignIn {
    SignIn(id: "si_test", status: status)
}

@MainActor
private func makeSignUp(_ status: SignUp.Status) -> SignUp {
    SignUp(
        id: "su_test",
        status: status,
        requiredFields: [],
        optionalFields: [],
        missingFields: [],
        unverifiedFields: [],
        verifications: [:],
        passwordEnabled: false,
        abandonAt: Date(),
    )
}

/// A fake conformer that records every call and its arguments, so we can assert the `ClerkAuthGateway` contract round-trips: each method is reachable, takes the declared arguments, and returns the declared type.
@MainActor
private final class RecordingGateway: ClerkAuthGateway {
    private(set) var appleCalls = 0
    private(set) var googleCalls = 0
    private(set) var startSignInEmails: [String] = []
    private(set) var startSignUpEmails: [String] = []
    private(set) var verifySignInCodes: [String] = []
    private(set) var verifySignUpCodes: [String] = []

    func signInWithApple() async throws {
        appleCalls += 1
    }

    func signInWithGoogle() async throws {
        googleCalls += 1
    }

    func startEmailSignIn(_ email: String) async throws -> SignIn {
        startSignInEmails.append(email)
        return makeSignIn(.needsFirstFactor)
    }

    func startEmailSignUp(_ email: String) async throws -> SignUp {
        startSignUpEmails.append(email)
        return makeSignUp(.missingRequirements)
    }

    func verify(signIn _: SignIn, code: String) async throws -> SignIn {
        verifySignInCodes.append(code)
        return makeSignIn(.complete)
    }

    func verify(signUp _: SignUp, code: String) async throws -> SignUp {
        verifySignUpCodes.append(code)
        return makeSignUp(.complete)
    }
}

/// `ClerkAuthGateway` is the irreducible seam over Clerk's SDK; `LiveClerkAuthGateway` is a logic-free passthrough whose calls only reach real network / OS sheets, so it can't be exercised headlessly. These tests pin what IS testable: the protocol contract (every method reachable with the declared signature) round-trips through a fake, and the live conformer constructs and conforms.
///
/// The live network / OS paths below this seam are covered by ClerkSignInServiceTests (gateway delegation + completion guards against a fake) and ClerkEmailAuthE2ETests (real email round-trip against the dev instance).
@MainActor
final class ClerkAuthGatewayTests: XCTestCase {
    func testProtocolContractRoundTrips() async throws {
        let gw = RecordingGateway()

        try await gw.signInWithApple()
        try await gw.signInWithGoogle()

        let signIn = try await gw.startEmailSignIn("a@b.com")
        let verifiedSignIn = try await gw.verify(signIn: signIn, code: "111111")

        let signUp = try await gw.startEmailSignUp("new@b.com")
        let verifiedSignUp = try await gw.verify(signUp: signUp, code: "222222")

        XCTAssertEqual(gw.appleCalls, 1)
        XCTAssertEqual(gw.googleCalls, 1)
        XCTAssertEqual(gw.startSignInEmails, ["a@b.com"])
        XCTAssertEqual(gw.startSignUpEmails, ["new@b.com"])
        XCTAssertEqual(gw.verifySignInCodes, ["111111"])
        XCTAssertEqual(gw.verifySignUpCodes, ["222222"])
        XCTAssertEqual(verifiedSignIn.status, .complete)
        XCTAssertEqual(verifiedSignUp.status, .complete)
    }

    func testLiveGatewayConstructsAndConforms() {
        let live: any ClerkAuthGateway = LiveClerkAuthGateway()
        _ = live
    }
}
