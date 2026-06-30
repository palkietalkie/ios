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

    /// Echo a realtime function-tool call to the backend. The tool call rides the iOS↔provider WS directly, so the backend never sees it otherwise — this is what makes `end_conversation` (and recall_* / web_fetch usage) visible in the events table and Slack. Fire-and-forget.
    func recordToolCall(sessionId: String?, name: String, query: String?) async throws {
        // `name` first so the Slack line leads with the tool, not the session UUID.
        struct Props: Codable {
            let name: String
            let query: String?
            let sessionId: String?
        }
        struct Body: Codable {
            let eventType: String
            let props: Props
        }
        let _: EmptyResponse = try await post(
            "/events",
            body: Body(
                eventType: "tool_call",
                props: Props(name: name, query: query.map { String($0.prefix(200)) }, sessionId: sessionId),
            ),
        )
    }

    /// Report a crash captured on the PREVIOUS launch (the app aborted, so it couldn't send live). Lands as an `app_crash` event the backend Slacks to #gtm with name + reason + top app frame. Only these concise fields go on the wire, the full symbolicated stack already lives in App Store Connect (scripts/asc/fetch_testflight_feedback.py pulls it), so duplicating it here would just flood Slack.
    func recordCrash(_ record: CrashRecord) async throws {
        struct Props: Codable {
            let kind: String
            let name: String
            let reason: String
            let topFrame: String
            let build: String
            let crashedAt: Date
        }
        struct Body: Codable {
            let eventType: String
            let props: Props
        }
        let _: EmptyResponse = try await post(
            "/events",
            body: Body(
                eventType: "app_crash",
                props: Props(
                    kind: record.kind,
                    name: record.name,
                    reason: String(record.reason.prefix(500)),
                    topFrame: record.topFrame,
                    build: record.build,
                    crashedAt: record.crashedAt,
                ),
            ),
        )
    }

    /// Record WHY a session ended (`tool` / `free_cap` / `user_left`) so the backend can measure the abnormal-end ratio. The end reason is a client-only decision (the realtime WS is iOS↔provider direct), so without this `/end` looks identical no matter what triggered it. Durable events row only, not Slacked. Fire-and-forget.
    func recordSessionEnd(sessionId: String, reason: String) async throws {
        struct Props: Codable {
            let sessionId: String
            let reason: String
        }
        struct Body: Codable {
            let eventType: String
            let props: Props
        }
        let _: EmptyResponse = try await post(
            "/events",
            body: Body(
                eventType: "session_ended",
                props: Props(sessionId: sessionId, reason: reason),
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
