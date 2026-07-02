@testable import PalkieTalkie
import XCTest

/// The response-lifecycle guard that fixes the free-cap-vs-active-response race: a wind-down (goodbye) requested mid-reply must defer its response.create until the in-flight reply finishes, or OpenAI rejects the second response and the goodbye is dropped.
final class ResponseLifecycleTests: XCTestCase {
    func testWindDownFiresImmediatelyWhenNoReplyInFlight() {
        var lifecycle = ResponseLifecycle()
        XCTAssertTrue(lifecycle.onWindDownRequested(), "no active reply → fire response.create now")
    }

    func testWindDownDeferredDuringReplyThenFiresOnDone() {
        var lifecycle = ResponseLifecycle()
        lifecycle.onResponseCreated()
        XCTAssertFalse(lifecycle.onWindDownRequested(), "reply in flight → defer, don't race it")
        XCTAssertTrue(lifecycle.onResponseDone(), "reply finished → now fire the deferred goodbye")
    }

    func testResponseDoneWithoutPendingWindDownFiresNothing() {
        var lifecycle = ResponseLifecycle()
        lifecycle.onResponseCreated()
        XCTAssertFalse(lifecycle.onResponseDone(), "no wind-down was requested → nothing to fire")
    }

    func testDeferredWindDownFiresOnlyOnce() {
        var lifecycle = ResponseLifecycle()
        lifecycle.onResponseCreated()
        _ = lifecycle.onWindDownRequested()
        XCTAssertTrue(lifecycle.onResponseDone(), "first done fires the deferred goodbye")
        lifecycle.onResponseCreated()
        XCTAssertFalse(lifecycle.onResponseDone(), "a later reply must not re-fire it")
    }
}
