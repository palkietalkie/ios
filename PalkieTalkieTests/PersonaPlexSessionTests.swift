@testable import PalkieTalkie
import XCTest

/// Lifecycle wrapper around PersonaPlexClient. Tests verify the protocol surface — open/close, send-control, send-audio,
/// stream accessors all forward to the underlying client. We don't open a real WebSocket; we just confirm the surface
/// type-checks against the RealtimeClient protocol and that close() doesn't crash without a prior open.
final class PersonaPlexSessionTests: XCTestCase {
    func testCloseBeforeOpenIsSafe() async {
        let session = PersonaPlexSession()
        await session.close() // should not crash
        // After close, calling close again is still a no-op.
        await session.close()
    }

    func testStreamsAccessibleBeforeOpen() async {
        let session = PersonaPlexSession()
        // The protocol requires these properties to exist and be readable even on a freshly-constructed session — they
        // back-fill into stale references the caller already holds.
        _ = await session.transcript
        _ = await session.inboundAudio
        _ = await session.errors
        _ = await session.bargeIn
    }

    func testBargeInStreamFinishesImmediately() async {
        let session = PersonaPlexSession()
        let stream = await session.bargeIn
        // PersonaPlex handles barge-in server-side, so the iOS-side stream is intentionally a no-op (finished
        // immediately). Iterating should produce zero elements.
        var count = 0
        for await _ in stream {
            count += 1
        }
        XCTAssertEqual(count, 0)
    }

    func testConformsToRealtimeClient() {
        let session: RealtimeClient = PersonaPlexSession()
        // If this compiles + runs without crashing, the conformance is intact.
        XCTAssertNotNil(session)
    }

    func testOpenInvalidURLThrows() async {
        let session = PersonaPlexSession()
        do {
            try await session.open(wsUrl: "")
            XCTFail("empty URL should throw")
        } catch {
            // expected — PersonaPlexClient.connect rejects URL(string: "") as invalidURL
        }
        do {
            try await session.open(wsUrl: "://garbage url with spaces")
            XCTFail("invalid URL should throw")
        } catch {
            // expected
        }
    }

    /// The PersonaPlexClient owns the WS lifecycle. Without a real open, sendControl/sendAudio should error with
    /// `.notConnected`.
    func testSendBeforeOpenErrors() async {
        let session = PersonaPlexSession()
        do {
            try await session.send(control: .start)
            XCTFail("send before open should throw notConnected")
        } catch {
            // expected
        }
        do {
            try await session.send(audio: Data([0xAA]))
            XCTFail("send before open should throw notConnected")
        } catch {
            // expected
        }
    }
}
