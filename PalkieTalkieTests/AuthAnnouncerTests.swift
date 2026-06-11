import Foundation
import os
@testable import PalkieTalkie
import XCTest

/// Wire-contract for `BackendAuthAnnouncer`: the pre-auth email parent goes out without a JWT, a success carries the Clerk bearer, a failure goes out unauthenticated (no session exists), and the backend's `thread_ts` decodes back out. The `send` closure is stubbed so nothing hits the network.
final class AuthAnnouncerTests: XCTestCase {
    private func captureRequest(
        auth: any Authing,
        responseJSON: String,
        event: AuthEvent,
    ) async -> (request: URLRequest?, result: String?) {
        let captured = OSAllocatedUnfairLock<URLRequest?>(initialState: nil)
        let announcer = BackendAuthAnnouncer(
            baseURL: URL(string: "https://api.test")!,
            auth: auth,
            send: { request in
                captured.withLock { $0 = request }
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(responseJSON.utf8), response)
            },
        )
        let result = await announcer.announce(event)
        return (captured.withLock { $0 }, result)
    }

    func testEmailCodeRequestedSendsNoBearerAndCarriesEmail() async throws {
        let (request, ts) = await captureRequest(
            auth: StubAuthing(),
            responseJSON: #"{"thread_ts": "999.9"}"#,
            event: .emailCodeRequested(email: "wes@gitauto.ai"),
        )
        let req = try XCTUnwrap(request)
        XCTAssertEqual(req.url?.absoluteString, "https://api.test/auth/announce")
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"), "the pre-auth parent has no session yet")
        let body = try XCTUnwrap(req.httpBody).asJSONObject()
        XCTAssertEqual(body["method"] as? String, "Email")
        XCTAssertEqual(body["outcome"] as? String, "requested")
        XCTAssertEqual(body["pending_email"] as? String, "wes@gitauto.ai")
        XCTAssertEqual(ts, "999.9", "the parent ts is returned so verify can thread under it")
    }

    func testSucceededAttachesBearerAndThreadTs() async throws {
        let (request, ts) = await captureRequest(
            auth: StubAuthing(token: "jwt-123"),
            responseJSON: #"{"thread_ts": "2"}"#,
            event: .succeeded(method: "Apple", threadTs: "999.9"),
        )
        let req = try XCTUnwrap(request)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-123")
        let body = try XCTUnwrap(req.httpBody).asJSONObject()
        XCTAssertEqual(body["method"] as? String, "Apple")
        XCTAssertEqual(body["outcome"] as? String, "succeeded")
        XCTAssertEqual(body["thread_ts"] as? String, "999.9")
        XCTAssertEqual(ts, "2")
    }

    func testSucceededWithoutTokenDoesNotSend() async throws {
        let captured = OSAllocatedUnfairLock<URLRequest?>(initialState: nil)
        let announcer = try BackendAuthAnnouncer(
            baseURL: XCTUnwrap(URL(string: "https://api.test")),
            auth: StubAuthing(token: nil),
            send: { request in
                captured.withLock { $0 = request }
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(), response)
            },
        )
        let ts = await announcer.announce(.succeeded(method: "Google", threadTs: nil))
        XCTAssertNil(ts)
        XCTAssertNil(captured.withLock { $0 }, "a success with no Clerk token must not hit the backend unauthenticated")
    }

    /// A failed attempt has no session, so it must NOT try to attach a bearer — it still reports, carrying the reason/email/thread.
    func testFailedSendsUnauthenticatedWithReason() async throws {
        let (request, _) = await captureRequest(
            auth: StubAuthing(token: nil),
            responseJSON: #"{"thread_ts": "3"}"#,
            event: .failed(method: "Email", reason: "missing requirements", email: "wes@gitauto.ai", threadTs: "999.9"),
        )
        let req = try XCTUnwrap(request)
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"), "a failure has no session, so no bearer")
        let body = try XCTUnwrap(req.httpBody).asJSONObject()
        XCTAssertEqual(body["method"] as? String, "Email")
        XCTAssertEqual(body["outcome"] as? String, "failed")
        XCTAssertEqual(body["reason"] as? String, "missing requirements")
        XCTAssertEqual(body["pending_email"] as? String, "wes@gitauto.ai")
        XCTAssertEqual(body["thread_ts"] as? String, "999.9")
    }
}

private extension Data {
    func asJSONObject() -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: self)) as? [String: Any] ?? [:]
    }
}
