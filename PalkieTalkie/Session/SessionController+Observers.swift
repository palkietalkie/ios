import Foundation
import OSLog

private let logger = Logger(subsystem: "com.palkietalkie", category: "conversation")

/// Stream-observer wiring (transcript / error / tool-call) for both providers, plus the backend failure report it triggers. Split out of SessionController to keep that type within SwiftLint's body-length budget.
extension SessionController {
    func startObserversForRealtime(client: RealtimeClient) async {
        let transcriptStream = await client.transcript
        let errorStream = await client.errors
        let transcriptTask = Task { [weak self] in
            for await chunk in transcriptStream {
                await MainActor.run {
                    self?.appendTranscript(chunk)
                }
            }
        }
        let errorTask = Task { [weak self] in
            for await message in errorStream {
                logger.error("realtime stream error: \(message, privacy: .public)")
                await self?.reportSessionError(reason: message)
                await self?.markServerSessionEnded()
                await MainActor.run {
                    self?.phase = .error(message)
                }
            }
        }
        let toolStream = await client.toolCalls
        let toolTask = Task { [weak self] in
            for await call in toolStream {
                // Runs in its own task, off the audio path — the model keeps talking while recall resolves (async, like a human remembering mid-sentence), then the result is fed back.
                await self?.handleToolCall(call, client: client)
            }
        }
        // Transport death (socket/network error in the recv loop) is the failure NWPathMonitor misses — the wifi→cellular handoff that drops the WS while the OS path stays "online". Route it into the same drop→reconnect path so a mid-call socket death recovers instead of going silent.
        let disconnectedStream = await client.disconnected
        let disconnectTask = Task { [weak self] in
            for await reason in disconnectedStream {
                // Detach the handling: teardown() inside handleTransportDisconnect cancels THIS observer task, and a cancelled task would abort the subsequent reconnect start(). A fresh unstructured task doesn't inherit that cancellation.
                Task { [weak self] in await self?.handleTransportDisconnect(reason: reason) }
            }
        }
        observerTasks = [transcriptTask, errorTask, toolTask, disconnectTask]
    }

    /// Fire-and-forget report of a realtime-session failure to the backend. The OpenAI audio WS runs iOS↔OpenAI directly, so this is the only server-side signal we get when a remote tester's session fails; a failed report must never disrupt the (already-failing) session, so errors are swallowed.
    func reportSessionError(reason: String) async {
        try? await backend.recordSessionError(
            sessionId: serverSessionId, provider: serverProvider ?? "unknown", reason: reason,
        )
    }

    /// Stamp `ended_at` on a session row we're abandoning without a graceful end — a failed start, an app error, or a drop right before we open a new row on reconnect. Without this the row created at /start is orphaned with a NULL ended_at forever. Best-effort; nil tokens because a dead session has no final usage to report.
    func markServerSessionEnded() async {
        guard let id = serverSessionId else { return }
        _ = try? await backend.endConversation(sessionId: id, inputTokens: nil, outputTokens: nil)
    }
}
