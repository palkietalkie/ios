@testable import PalkieTalkie
import XCTest

/// Cover the production `Authing` conformer (`ClerkAuthAdapter`) + the test conformer (`StubAuthing`). Clerk's static singleton state isn't injectable, so we can only black-box the signed-out branch of the adapter — tests confirm it returns nil getters and the right error type without crashing. `StubAuthing` is covered directly because it's the surface every View-test uses.
final class ClerkAuthTests: XCTestCase {
    // MARK: - ClerkAuthAdapter (signed-out branch in test bundle)

    func testAdapterSignedOutDefaults() async {
        let adapter = ClerkAuthAdapter()
        let userId = await adapter.userId
        let email = await adapter.email
        XCTAssertNil(userId)
        XCTAssertNil(email)
    }

    func testAdapterSessionTokenThrowsWhenSignedOut() async {
        let adapter = ClerkAuthAdapter()
        do {
            _ = try await adapter.sessionToken()
            XCTFail("expected AuthTokenError when no session")
        } catch let error as AuthTokenError {
            XCTAssertEqual(error.reason, "no Clerk session")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testAdapterSignOutDoesNotCrashWhenSignedOut() async {
        let adapter = ClerkAuthAdapter()
        await adapter.signOut()
    }

    // MARK: - StubAuthing (the test seam)

    func testStubAuthingReturnsConfiguredToken() async throws {
        let stub = StubAuthing(token: "ek_test_123")
        let token = try await stub.sessionToken()
        XCTAssertEqual(token, "ek_test_123")
    }

    func testStubAuthingThrowsWhenTokenNil() async {
        let stub = StubAuthing(token: nil)
        do {
            _ = try await stub.sessionToken()
            XCTFail("expected throw")
        } catch let error as AuthTokenError {
            XCTAssertEqual(error.reason, "stub: no token")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testStubAuthingUserIdAndEmail() async {
        let stub = StubAuthing(userId: "u_42", email: "wes@example.test")
        let userId = await stub.userId
        let email = await stub.email
        XCTAssertEqual(userId, "u_42")
        XCTAssertEqual(email, "wes@example.test")
    }

    func testStubAuthingRecordsSignOut() async {
        let stub = StubAuthing()
        await stub.signOut()
        await stub.signOut()
        XCTAssertEqual(stub.signOutCount, 2)
    }

    // MARK: - AppEnvironment factories

    func testProductionBackendAPIBuilds() {
        // Smoke test: the production factory wires a transport + Clerk-backed adapter without crashing.
        let api = AppEnvironment.makeProductionBackendAPI()
        XCTAssertNotNil(api.baseURL)
    }
}
