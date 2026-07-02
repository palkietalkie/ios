import Foundation

/// One OpenAI realtime control event, decoded from the data-channel JSON. A pure value type so the whole protocol-decoding surface (which event type, field extraction, benign-vs-real error, token-usage math, tool-call shape) is unit-tested without a live peer connection. OpenAIWebRTCClient.handleEvent just dispatches these onto its streams; all the logic lives here.
enum RealtimeEvent {
    case ready
    case responseCreated
    case responseDone(RealtimeUsage)
    case personaTranscriptDelta(String)
    case userTranscript(String)
    case speechStarted
    case toolCall(ToolCall)
    /// nil message = a benign error (a response.create that raced an already-active response, i.e. the free-cap wrap-up hint landing mid-turn); dispatch drops it instead of terminating the session.
    case error(String?)

    /// Coarse label for the per-event diagnostic log (no associated values, so transcript/tool content never lands in os_log).
    var logLabel: String {
        switch self {
        case .ready: "ready"
        case .responseCreated: "response.created"
        case .responseDone: "response.done"
        case .personaTranscriptDelta: "transcript.delta"
        case .userTranscript: "input_transcript"
        case .speechStarted: "speech_started"
        case .toolCall: "function_call"
        case let .error(message): message == nil ? "error(benign)" : "error"
        }
    }
}

/// Decode one data-channel message into a RealtimeEvent, or nil when it isn't an event we act on (malformed JSON, no type, an empty transcript delta, or an event type we ignore). Same event shapes the WS path parsed, minus response.output_audio.delta (WebRTC plays tutor audio via its media track, not app-decoded bytes).
func parseRealtimeEvent(_ data: Data) -> RealtimeEvent? {
    guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let type = parsed["type"] as? String
    else { return nil }
    switch type {
    case "session.created", "session.updated":
        return .ready
    case "response.created":
        return .responseCreated
    case "input_audio_buffer.speech_started":
        return .speechStarted
    case "response.output_audio_transcript.delta":
        guard let delta = parsed["delta"] as? String, !delta.isEmpty else { return nil }
        return .personaTranscriptDelta(delta)
    case "conversation.item.input_audio_transcription.completed":
        guard let transcript = parsed["transcript"] as? String, !transcript.isEmpty else { return nil }
        return .userTranscript(transcript)
    case "response.done":
        return .responseDone(usageDelta(from: parsed))
    case "response.function_call_arguments.done":
        guard let call = parseToolCall(from: parsed) else { return nil }
        return .toolCall(call)
    case "error":
        return .error(surfacedError(from: parsed))
    default:
        return nil
    }
}

/// One response.done's token usage (0 if the event lacks a usage block). Dispatch adds this to the running total.
func usageDelta(from parsed: [String: Any]) -> RealtimeUsage {
    guard let response = parsed["response"] as? [String: Any],
          let usage = response["usage"] as? [String: Any]
    else { return .zero }
    return RealtimeUsage(
        inputTokens: usage["input_tokens"] as? Int ?? 0,
        outputTokens: usage["output_tokens"] as? Int ?? 0,
    )
}

/// The message to surface (and terminate the session on) for an error event, or nil if it's benign and should be dropped. Benign = a response.create that raced an already-active response (the free-cap wrap-up hint landing mid-turn) — the AI is already replying, so it isn't a real failure.
func surfacedError(from parsed: [String: Any]) -> String? {
    let nested = parsed["error"] as? [String: Any]
    let code = nested?["code"] as? String
    let message = (nested?["message"] as? String) ?? (parsed["message"] as? String) ?? "unknown error"
    if code == "conversation_already_has_active_response" || message.contains("active response in progress") {
        return nil
    }
    return message
}

/// A tool/function call the model requested, or nil if the event lacks the call id or name. The `query` argument is pulled out of the JSON-encoded arguments string (the only argument our tools take today).
func parseToolCall(from parsed: [String: Any]) -> ToolCall? {
    guard let callId = parsed["call_id"] as? String, let name = parsed["name"] as? String else { return nil }
    let args = parsed["arguments"] as? String ?? "{}"
    let query = ((try? JSONSerialization.jsonObject(
        with: Data(args.utf8),
    )) as? [String: Any])?["query"] as? String ?? ""
    return ToolCall(callId: callId, name: name, query: query)
}
