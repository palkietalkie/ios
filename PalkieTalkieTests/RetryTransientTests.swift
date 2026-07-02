@testable import PalkieTalkie
import XCTest

/// Transient-network classification + retry for the WebRTC SDP handshake POST. The `-1005` networkConnectionLost that killed the handshake must be retried; a real failure (bad HTTP, auth) must not be.
final class RetryTransientTests: XCTestCase {
    func testTransientNetworkErrorsClassified() {
        XCTAssertTrue(
            isTransientNetworkError(URLError(.networkConnectionLost)),
            "-1005 killed the SDP handshake; must be retryable",
        )
        XCTAssertTrue(isTransientNetworkError(URLError(.timedOut)))
        XCTAssertTrue(isTransientNetworkError(URLError(.notConnectedToInternet)))
        XCTAssertFalse(
            isTransientNetworkError(URLError(.userAuthenticationRequired)),
            "auth failure is real, don't retry",
        )
        XCTAssertFalse(
            isTransientNetworkError(OpenAIWebRTCError.handshakeFailed),
            "a bad HTTP response is not transient",
        )
    }

    func testRetryTransientRecoversAfterHiccups() async throws {
        var attempts = 0
        let result = try await retryTransient(maxAttempts: 3) { () async throws -> String in
            attempts += 1
            if attempts < 3 { throw URLError(.networkConnectionLost) }
            return "ok"
        }
        XCTAssertEqual(result, "ok")
        XCTAssertEqual(attempts, 3, "retried past the two transient failures")
    }

    func testRetryTransientGivesUpAfterMaxAttempts() async {
        var attempts = 0
        do {
            _ = try await retryTransient(maxAttempts: 2) { () async throws -> String in
                attempts += 1
                throw URLError(.networkConnectionLost)
            }
            XCTFail("should have thrown after exhausting attempts")
        } catch {
            XCTAssertTrue(error is URLError)
        }
        XCTAssertEqual(attempts, 2, "stopped at maxAttempts")
    }

    func testRetryTransientDoesNotRetryRealFailure() async {
        var attempts = 0
        do {
            _ = try await retryTransient(maxAttempts: 3) { () async throws -> String in
                attempts += 1
                throw OpenAIWebRTCError.handshakeFailed
            }
            XCTFail("a non-transient error should throw immediately")
        } catch {}
        XCTAssertEqual(attempts, 1, "a real failure isn't retried")
    }
}
