import Foundation
import OSLog

private let logger = Logger(subsystem: "com.palkietalkie", category: "conversation")

/// Conversation-time recall (realtime tool calls), split out of SessionController to keep that type within SwiftLint's body-length budget.
extension SessionController {
    /// Fulfill a realtime tool call against the backend recall endpoints and feed the result back to the model. Errors degrade to a short note rather than throwing, so a failed lookup never derails the conversation.
    func handleToolCall(_ call: ToolCall, client: RealtimeClient) async {
        // Echo every tool call to the backend (durable events row + live Slack). The realtime WS is iOS↔provider direct, so this is the backend's only window into what the model is doing mid-conversation, especially end_conversation, which otherwise hangs up the session with no server-side trace.
        _ = try? await backend.recordToolCall(
            sessionId: serverSessionId,
            name: call.name,
            query: call.query.isEmpty ? nil : call.query,
        )
        // The user signalled they're done. Don't send a tool result (we're tearing down); record it durably so end() can label the session_ended event `tool` even after the navigator clears endRequestedByTool.
        if call.name == "end_conversation" {
            modelRequestedEnd = true
            // Let the model's goodbye finish playing before flagging the navigator to leave — tearing down now cuts it off, and the user never hears it (the transcript arrives well ahead of the audio, so we wait on the audio drain, not the transcript).
            Task { [weak self] in
                await self?.waitForAIToFinishSpeaking()
                self?.endRequestedByTool = true
            }
            return
        }
        let output: String
        do {
            switch call.name {
            case "recall_facts":
                output = try await backend.recallFacts(query: call.query)
            case "recall_past_conversations":
                output = try await backend.recallConversations(query: call.query)
            case "search_transcripts":
                output = try await backend.searchTranscripts(query: call.query)
            case "web_fetch":
                output = try await backend.webFetch(url: call.query)
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
