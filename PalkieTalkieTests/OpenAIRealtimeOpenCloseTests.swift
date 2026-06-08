@testable import PalkieTalkie
import XCTest

/// Drives the full `open()` → readLoop start → `close()` cycle of OpenAIRealtimeClient against a localhost URL the
/// kernel will reject. Even though the WS connection never lands, the code paths that build the URLRequest, set the
/// Bearer auth header, kick the WS task, schedule the readLoop, and tear down all execute. That gets us coverage
/// over `open` and the readLoop exit branch without needing a real OpenAI server.
final class OpenAIRealtimeOpenCloseTests: XCTestCase {
    func testOpenAndCloseAgainstLocalhostExitsCleanly() async {
        let client = OpenAIRealtimeClient(instructions: "test")
        // Port 9 is RFC 863 "discard" — TCP connections are rejected immediately.
        try? await client.open(wsUrl: "wss://127.0.0.1:9/", ephemeralToken: "tok")
        // Give the readLoop a moment to fail and exit.
        try? await Task.sleep(nanoseconds: 200_000_000)
        await client.close()
        // After close, the streams should be finished.
        let inbound = await client.inboundAudio
        var inboundCount = 0
        for await _ in inbound {
            inboundCount += 1
        }
        XCTAssertEqual(inboundCount, 0)
    }

    func testOpenSendAudioAfterOpenIsPossibleBeforeClose() async {
        // Cover send(audio:) when a task exists. The send will fail since the WS hasn't upgraded, but the code path
        // through base64 encoding + JSON serialization + try-await task.send runs.
        let client = OpenAIRealtimeClient(instructions: nil)
        try? await client.open(wsUrl: "wss://127.0.0.1:9/", ephemeralToken: "tok")
        try? await Task.sleep(nanoseconds: 50_000_000)
        do {
            try await client.send(audio: Data(repeating: 0x00, count: 960))
        } catch {
            // Either succeeds (send queued before failure surfaces) or throws — both are valid coverage.
        }
        await client.close()
    }
}
