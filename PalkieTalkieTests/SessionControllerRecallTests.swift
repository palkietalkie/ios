@testable import PalkieTalkie
import XCTest

/// Pairs SessionController+Recall.swift.
@MainActor
final class SessionControllerRecallTests: XCTestCase {
    /// A realtime tool call must route to the matching backend recall method and feed the result back to the model via submitToolOutput — the conversation-time KG/recall mechanism.
    func testToolCallRoutesToBackendAndSubmitsOutput() async {
        let rig = makeSessionControllerRig()
        await rig.controller.start()
        await rig.session.emit(toolCall: ToolCall(callId: "c1", name: "recall_facts", query: "naoto"))
        try? await Task.sleep(nanoseconds: 80_000_000)

        let calls = await rig.backend.recallCalls
        XCTAssertEqual(calls.first?.name, "recall_facts")
        XCTAssertEqual(calls.first?.query, "naoto")
        let outputs = await rig.session.submittedOutputs
        XCTAssertEqual(outputs.first?.callId, "c1")
        XCTAssertEqual(outputs.first?.output, "FACTS")
    }
}
