import OSLog
@testable import PalkieTalkie
import XCTest

/// Render-then-refresh classifier: a failed cached-content refresh surfaces ONLY a decode/contract drift; slow, offline, timed-out, and HTTP-error refreshes are swallowed (the view keeps its cached/empty content) and logged.
final class BackendErrorRenderThenRefreshTests: XCTestCase {
    func testIsContractFailureOnlyForDecoding() {
        XCTAssertTrue(BackendError.decoding("nodes/edges shape changed").isContractFailure)
        XCTAssertFalse(BackendError.http(500, "boom").isContractFailure)
        XCTAssertFalse(BackendError.http(0, "no response").isContractFailure)
        XCTAssertFalse(BackendError.notAuthenticated(reason: "expired").isContractFailure)
        XCTAssertFalse(BackendError.invalidURL.isContractFailure)
    }

    func testContentRefreshErrorSurfacesContractDriftOnly() {
        let logger = Logger(subsystem: "com.palkietalkie.tests", category: "render-then-refresh")
        // A contract drift is a real bug → return a message for the view to show.
        XCTAssertNotNil(contentRefreshError(BackendError.decoding("shape drift"), refreshing: "kg", log: logger))
        // Slow / offline / timed-out / HTTP error → keep cached content (nil), don't replace it with an error.
        XCTAssertNil(contentRefreshError(BackendError.http(500, "boom"), refreshing: "stats", log: logger))
        XCTAssertNil(contentRefreshError(URLError(.timedOut), refreshing: "today", log: logger))
        XCTAssertNil(contentRefreshError(URLError(.notConnectedToInternet), refreshing: "history", log: logger))
    }
}
