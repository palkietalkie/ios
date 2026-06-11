import Foundation
import OSLog

private let logger = Logger(subsystem: "com.palkietalkie", category: "conversation")

/// Conversation-time recall (realtime tool calls), split out of SessionController to keep that type within SwiftLint's body-length budget.
extension SessionController {
    /// Fulfill a realtime tool call against the backend recall endpoints and feed the result back to the model. Errors degrade to a short note rather than throwing, so a failed lookup never derails the conversation.
    func handleToolCall(_ call: ToolCall, client: RealtimeClient) async {
        let output: String
        do {
            switch call.name {
            case "recall_facts":
                output = try await backend.recallFacts(query: call.query)
            case "recall_past_conversations":
                output = try await backend.recallConversations(query: call.query)
            case "search_transcripts":
                output = try await backend.searchTranscripts(query: call.query)
            default:
                output = "Unknown tool."
            }
        } catch {
            logger
                .error(
                    "tool call \(call.name, privacy: .public) failed: \(String(describing: error), privacy: .public)",
                )
            output = "That lookup isn't available right now."
        }
        await client.submitToolOutput(callId: call.callId, output: output)
    }
}
