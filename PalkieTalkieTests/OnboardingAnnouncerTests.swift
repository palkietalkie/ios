import Foundation
import os
@testable import PalkieTalkie
import XCTest

/// Wire-contract for `BackendOnboardingAnnouncer`: posts step + phase to /onboarding/announce with the Clerk bearer + name, threads under the given ts, decodes the returned thread ts, and skips entirely when there's no session.
final class OnboardingAnnouncerTests: XCTestCase {
    func testAnnounceSendsStepPhaseIdentityAndThread() async throws {
        let captured = OSAllocatedUnfairLock<URLRequest?>(initialState: nil)
        let announcer = try BackendOnboardingAnnouncer(
            baseURL: XCTUnwrap(URL(string: "https://api.test")),
            auth: StubAuthing(token: "jwt-1", preferredName: "Wes Nishio"),
            send: { request in
                captured.withLock { $0 = request }
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(#"{"thread_ts": "55.5"}"#.utf8), response)
            },
        )
        let ts = await announcer.announce(step: "goals", phase: "completed", threadTs: "10.1")
        let req = try XCTUnwrap(captured.withLock { $0 })
        XCTAssertEqual(req.url?.absoluteString, "https://api.test/onboarding/announce")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-1")
        let body = try XCTUnwrap(req.httpBody).asJSONObject()
        XCTAssertEqual(body["step"] as? String, "goals")
        XCTAssertEqual(body["phase"] as? String, "completed")
        XCTAssertEqual(body["thread_ts"] as? String, "10.1")
        XCTAssertEqual(body["preferred_name"] as? String, "Wes Nishio")
        XCTAssertEqual(ts, "55.5")
    }

    func testAnnounceWithoutSessionSkips() async throws {
        let announcer = try BackendOnboardingAnnouncer(
            baseURL: XCTUnwrap(URL(string: "https://api.test")),
            auth: StubAuthing(token: nil),
            send: { _ in (Data(), URLResponse()) },
        )
        let ts = await announcer.announce(step: "intro", phase: "viewed", threadTs: nil)
        XCTAssertNil(ts, "no Clerk session → no report")
    }

    func testNoopAnnouncerIsInert() async {
        let ts = await NoopOnboardingAnnouncer().announce(step: "intro", phase: "viewed", threadTs: nil)
        XCTAssertNil(ts)
    }
}

private extension Data {
    func asJSONObject() -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: self)) as? [String: Any] ?? [:]
    }
}
