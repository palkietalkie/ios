@testable import PalkieTalkie
import XCTest

/// Drives `PersonaPlexClient.connect()` + `close()` against a localhost URL the kernel rejects. Exercises the URL parsing, stream setup, WS task creation, handshake-send, and readLoop spin-up paths without needing a real PersonaPlex server.
final class PersonaPlexClientConnectTests: XCTestCase {
    func testConnectAndCloseAgainstLocalhostExitsCleanly() async {
        let client = PersonaPlexClient()
        // Port 9 (RFC 863 discard) rejects immediately on most kernels.
        try? await client.connect(wsUrl: "wss://127.0.0.1:9/")
        try? await Task.sleep(nanoseconds: 200_000_000)
        await client.close()
        // Streams should be finished.
        let inbound = await client.inboundAudio
        var count = 0
        for await _ in inbound {
            count += 1
        }
        XCTAssertEqual(count, 0)
    }

    func testSendAfterConnectExercisesSendPath() async {
        let client = PersonaPlexClient()
        try? await client.connect(wsUrl: "wss://127.0.0.1:9/")
        try? await Task.sleep(nanoseconds: 50_000_000)
        // Multiple sends exercise the per-frame logging counter (#1, #2, #3, then every 50th).
        for _ in 0 ..< 3 {
            try? await client.sendAudio(Data(repeating: 0x00, count: 16))
        }
        try? await client.sendControl(.endTurn)
        try? await client.endTurn()
        await client.close()
    }
}
