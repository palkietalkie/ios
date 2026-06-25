import Foundation

/// Client-side telemetry + session-health events, all POSTed to `/events` (one row per call). Fire-and-forget — failures shouldn't abort the conversation.
extension BackendAPI {
    /// Cold-start telemetry. Fire-and-forget — failures shouldn't abort the conversation.
    func recordColdStart(
        durationMs: Int,
        phaseTimings: ColdStartTimings,
        sessionId: String,
    ) async throws {
        struct Props: Codable {
            let durationMs: Int
            let phaseTimings: ColdStartTimings
            let sessionId: String
        }
        struct Body: Codable {
            let eventType: String
            let props: Props
        }
        let _: EmptyResponse = try await post(
            "/events",
            body: Body(
                eventType: "cold_start_complete",
                props: Props(
                    durationMs: durationMs,
                    phaseTimings: phaseTimings,
                    sessionId: sessionId,
                ),
            ),
        )
    }

    func recordPitchRange(sessionId: String, minHz: Float, maxHz: Float) async throws {
        struct Props: Codable {
            let sessionId: String
            let minHz: Float
            let maxHz: Float
        }
        struct Body: Codable {
            let eventType: String
            let props: Props
        }
        let _: EmptyResponse = try await post(
            "/events",
            body: Body(
                eventType: "pitch_range",
                props: Props(sessionId: sessionId, minHz: minHz, maxHz: maxHz),
            ),
        )
    }

    /// Per-category counts of the tutor's reactions this session (detected live on-device): positives (laugh/cheer/gasp) and negatives (sigh/groan). Stored as one event row, the saved per-user record we also mine internally for struggling users. `/stats` weights and combines them (negatives subtract) into the Affinity metric. Weights live server-side so the formula stays tunable without an app update.
    func recordAIEmotions(
        sessionId: String, laugh: Int, cheer: Int, gasp: Int, sigh: Int, groan: Int,
    ) async throws {
        struct Props: Codable {
            let sessionId: String
            let laugh: Int
            let cheer: Int
            let gasp: Int
            let sigh: Int
            let groan: Int
        }
        struct Body: Codable {
            let eventType: String
            let props: Props
        }
        let _: EmptyResponse = try await post(
            "/events",
            body: Body(
                eventType: "ai_emotion",
                props: Props(
                    sessionId: sessionId, laugh: laugh, cheer: cheer, gasp: gasp, sigh: sigh, groan: groan,
                ),
            ),
        )
    }

    /// Report a realtime-session failure (WS error event, abnormal disconnect, or no-first-audio timeout) to the backend so failures are visible for testers in the wild, not just in a cabled device log. The OpenAI audio WS runs iOS↔OpenAI directly, so without this the backend has zero signal when "mic goes green but nothing happens".
    func recordSessionError(sessionId: String?, provider: String, reason: String) async throws {
        struct Props: Codable {
            let sessionId: String?
            let provider: String
            let reason: String
        }
        struct Body: Codable {
            let eventType: String
            let props: Props
        }
        let _: EmptyResponse = try await post(
            "/events",
            body: Body(
                eventType: "session_error",
                props: Props(sessionId: sessionId, provider: provider, reason: String(reason.prefix(500))),
            ),
        )
    }
}

/// Per-phase milliseconds for one cold-start. Sums roughly to total minus parallelism gaps. Backend stores these in
/// `events.props` for percentile analysis across users.
struct ColdStartTimings: Codable {
    let gatherContextMs: Int
    let backendStartMs: Int
    let websocketConnectMs: Int
    let firstAudioMs: Int
}
