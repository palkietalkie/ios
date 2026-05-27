import Foundation

/// Records the cold-start timeline of one conversation and posts it to backend `/events` once the model emits its first
/// audio chunk.
///
/// Single responsibility: turn 4 phase-end timestamps into one `cold_start_complete` event.
///
/// Why a separate file: keeps SessionController focused on phase machine + collaborator wiring. Telemetry is async
/// fire-and-forget by nature and doesn't belong in the orchestrator's critical path.
enum ColdStartReporter {
    static func scheduleReport(
        backend: ConversationBackend,
        inboundAudio: AsyncStream<Data>,
        sessionId: String,
        t0: Date,
        tGatherEnd: Date,
        tStartEnd: Date,
        tConnectEnd: Date
    ) {
        Task.detached(priority: .background) {
            for await _ in inboundAudio {
                let tFirstAudio = Date()
                let total = Int(tFirstAudio.timeIntervalSince(t0) * 1000)
                let timings = ColdStartTimings(
                    gatherContextMs: Int(tGatherEnd.timeIntervalSince(t0) * 1000),
                    backendStartMs: Int(tStartEnd.timeIntervalSince(tGatherEnd) * 1000),
                    websocketConnectMs: Int(tConnectEnd.timeIntervalSince(tStartEnd) * 1000),
                    firstAudioMs: Int(tFirstAudio.timeIntervalSince(tConnectEnd) * 1000)
                )
                try? await backend.recordColdStart(
                    durationMs: total,
                    phaseTimings: timings,
                    sessionId: sessionId
                )
                // Only the first audio chunk matters for cold-start measurement; we exit after one report so the task
                // doesn't sit forever waiting for the stream to end.
                break
            }
        }
    }
}
