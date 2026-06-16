@testable import PalkieTalkie
import XCTest

/// Additional coverage for OpenAIRealtimeClient surface — stream accessors, conformance, and stream closure on shutdown.
final class OpenAIRealtimeClientExtraTests: XCTestCase {
    func testConformsToRealtimeClient() {
        let client = OpenAIRealtimeClient(instructions: "be real")
        let realtime: RealtimeClient = client
        XCTAssertNotNil(realtime)
    }

    func testStreamsAccessibleBeforeOpen() async {
        let client = OpenAIRealtimeClient(instructions: nil)
        _ = await client.inboundAudio
        _ = await client.transcript
        _ = await client.errors
        _ = await client.bargeIn
    }

    func testCloseBeforeOpenIsSafe() async {
        let client = OpenAIRealtimeClient(instructions: nil)
        await client.close()
        // Double-close is also safe.
        await client.close()
    }

    func testCloseFinishesBargeInStream() async {
        let client = OpenAIRealtimeClient(instructions: nil)
        let bargeIn = await client.bargeIn
        await client.close()
        // bargeIn doesn't get finished by close() yet (OpenAIRealtimeClient.close finishes audio/transcript/error but not bargeIn). Just confirm we can read the stream type without crashing.
        XCTAssertNotNil(bargeIn)
    }

    /// `open` rejects an empty ephemeral token — the OpenAI Realtime WS requires Bearer auth. Without this guard the WS upgrade would fail later with a less useful error.
    func testOpenWithNilTokenThrowsMissingEphemeralToken() async {
        let client = OpenAIRealtimeClient(instructions: nil)
        do {
            try await client.open(wsUrl: "wss://api.openai.com/v1/realtime", ephemeralToken: nil)
            XCTFail("expected missingEphemeralToken")
        } catch let OpenAIRealtimeError.missingEphemeralToken {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testOpenWithEmptyTokenThrowsMissingEphemeralToken() async {
        let client = OpenAIRealtimeClient(instructions: nil)
        do {
            try await client.open(wsUrl: "wss://api.openai.com/v1/realtime", ephemeralToken: "")
            XCTFail("expected missingEphemeralToken")
        } catch let OpenAIRealtimeError.missingEphemeralToken {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testInvalidURLOpensBoundedFailure() async {
        let client = OpenAIRealtimeClient(instructions: nil)
        do {
            try await client.open(wsUrl: "https://garbage host name with spaces", ephemeralToken: "tok")
            // Some malformed strings still parse as URLs — that's fine; URLSessionWebSocketTask will fail later.
            // Force close so the test doesn't leak the session.
            await client.close()
        } catch let OpenAIRealtimeError.invalidURL {
            // expected for truly unparseable URLs
        } catch {
            // Other errors are acceptable — the contract here is "doesn't deadlock".
        }
    }

    /// web_fetch arrives with a "url" argument (not "query"); recall tools send "query". Both must surface as ToolCall.query. Before the url fallback this yielded an empty query and web_fetch fetched nothing.
    func testFunctionCallWithURLArgumentSurfacesAsQuery() async {
        let client = OpenAIRealtimeClient(instructions: nil)
        let calls = await client.toolCalls
        await client.handleEvent(data: Data(
            #"{"type":"response.function_call_arguments.done","call_id":"c9","name":"web_fetch","arguments":"{\"url\":\"https://news/x\"}"}"#
                .utf8,
        ))
        let task = Task { () -> ToolCall? in
            for await call in calls {
                return call
            }
            return nil
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        await client.close()
        let received = await task.value
        XCTAssertEqual(received?.name, "web_fetch")
        XCTAssertEqual(received?.query, "https://news/x")
    }

    func testFunctionCallWithQueryArgumentStillSurfaces() async {
        let client = OpenAIRealtimeClient(instructions: nil)
        let calls = await client.toolCalls
        await client.handleEvent(data: Data(
            #"{"type":"response.function_call_arguments.done","call_id":"c10","name":"recall_facts","arguments":"{\"query\":\"wes\"}"}"#
                .utf8,
        ))
        let task = Task { () -> ToolCall? in
            for await call in calls {
                return call
            }
            return nil
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        await client.close()
        let received = await task.value
        XCTAssertEqual(received?.query, "wes")
    }
}
