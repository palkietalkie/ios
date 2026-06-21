import Foundation
import OSLog

private let logger = Logger(subsystem: "com.palkietalkie", category: "conversation")

/// Stream-observer wiring (transcript / error / tool-call) for both providers, plus the backend failure report it triggers. Split out of SessionController to keep that type within SwiftLint's body-length budget.
extension SessionController {
    func startObservers(session: PersonaPlexSessionType) async {
        let transcriptStream = await session.transcript
        let errorStream = await session.errors
        let transcriptTask = Task { [weak self] in
            for await chunk in transcriptStream {
                await MainActor.run {
                    self?.appendTranscript(chunk)
                }
            }
        }
        let errorTask = Task { [weak self] in
            for await message in errorStream {
                logger.error("personaplex stream error: \(message, privacy: .public)")
                await self?.reportSessionError(reason: message)
                await MainActor.run {
                    self?.phase = .error(message)
                }
            }
        }
        observerTasks = [transcriptTask, errorTask]
    }

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
        observerTasks = [transcriptTask, errorTask, toolTask]
    }

    /// Fire-and-forget report of a realtime-session failure to the backend. The OpenAI audio WS runs iOS↔OpenAI directly, so this is the only server-side signal we get when a remote tester's session fails; a failed report must never disrupt the (already-failing) session, so errors are swallowed.
    func reportSessionError(reason: String) async {
        try? await backend.recordSessionError(
            sessionId: serverSessionId, provider: serverProvider ?? "unknown", reason: reason,
        )
    }
}
