@testable import PalkieTalkie
import XCTest

/// The RealtimeClient protocol defaults that providers and test doubles inherit when they don't override them: PersonaPlex has no tools/usage, neither PersonaPlex nor a double measures output amplitude, and the disconnected stream is WebRTC/WS-specific. OpenAIWebRTCClient overrides outputLevel/disconnected; this proves the DEFAULTS behave (a bare conformer gets 0 / .zero / empty streams / a no-op), so those paths don't silently break.
final class RealtimeClientTests: XCTestCase {
    /// Conforms to RealtimeClient implementing ONLY the members that have no default, so the defaults are the ones under test.
    private final class BareClient: RealtimeClient {
        func open(wsUrl _: String, ephemeralToken _: String?) async throws {}
        func close() async {}
        func send(audio _: Data) async throws {}
        func waitForServerReady() async {}
        func injectSystemHint(_: String) async {}
        var inboundAudio: AsyncStream<Data> {
            get async { AsyncStream { $0.finish() } }
        }

        var transcript: AsyncStream<TranscriptChunk> {
            get async { AsyncStream { $0.finish() } }
        }

        var errors: AsyncStream<String> {
            get async { AsyncStream { $0.finish() } }
        }

        var bargeIn: AsyncStream<Void> {
            get async { AsyncStream { $0.finish() } }
        }
    }

    func testOutputLevelDefaultsToZero() {
        XCTAssertEqual(
            BareClient().outputLevel,
            0,
            "a provider that doesn't measure amplitude (PersonaPlex, doubles) reports 0",
        )
    }

    func testUsageDefaultsToZero() async {
        let usage = await BareClient().usage
        XCTAssertEqual(usage, .zero, "a provider that bills elsewhere (PersonaPlex/Modal) reports no token usage")
    }

    func testToolCallsDefaultsToEmptyStream() async {
        var count = 0
        for await _ in await BareClient().toolCalls {
            count += 1
        }
        XCTAssertEqual(count, 0, "no function calling → an empty (finished) stream, not a hang")
    }

    func testDisconnectedDefaultsToEmptyStream() async {
        var count = 0
        for await _ in await BareClient().disconnected {
            count += 1
        }
        XCTAssertEqual(count, 0, "a provider that doesn't surface transport death → empty stream")
    }

    func testSubmitToolOutputDefaultIsNoOp() async {
        await BareClient()
            .submitToolOutput(callId: "c1", output: "result") // must not crash on a provider without tools
    }
}
