import Foundation
import OSLog

private let logger = Logger(subsystem: "com.palkietalkie", category: "openai-realtime")

enum OpenAIRealtimeError: Error {
    case invalidURL
    case notConnected
    case missingEphemeralToken
    case socketClosed(URLSessionWebSocketTask.CloseCode)
}

/// OpenAI Realtime WebSocket wire format (JSON events, all base64 strings for audio).
///
/// Client → server (we send):
///   `session.update`            — set instructions / voice / formats. Sent once after WS upgrade.
///   `input_audio_buffer.append` — base64-encoded raw PCM16 (24kHz mono little-endian) per frame.
///
/// Server → client (we receive):
///   `response.audio.delta`           — base64-encoded raw PCM16 chunk to play through the speaker.
///   `response.audio_transcript.delta` — text token chunk for the live transcript.
///   `response.audio_transcript.done` — terminator; we mostly ignore (display happens token-by-token).
///   `error`                          — server-side error string.
///
/// We do NOT speak the binary Ogg-Opus protocol PersonaPlex uses. Caller passes raw PCM16 little-endian to `send(audio:)`; we base64-encode and wrap in the JSON event. `inboundAudio` yields raw PCM16 chunks for the speaker side.
actor OpenAIRealtimeClient: RealtimeClient {
    private var task: URLSessionWebSocketTask?
    private let session: URLSession

    private var transcriptStream: AsyncStream<TranscriptChunk>?
    private var transcriptContinuation: AsyncStream<TranscriptChunk>.Continuation?
    private var audioStream: AsyncStream<Data>?
    private var audioContinuation: AsyncStream<Data>.Continuation?
    private var errorStream: AsyncStream<String>?
    private var errorContinuation: AsyncStream<String>.Continuation?
    private var bargeInStream: AsyncStream<Void>?
    private var bargeInContinuation: AsyncStream<Void>.Continuation?
    private var toolCallStream: AsyncStream<ToolCall>?
    private var toolCallContinuation: AsyncStream<ToolCall>.Continuation?
    // AsyncStream's two halves: SessionController iterates the `stream`; the recv loop / close push into the `continuation`. We keep the continuation so the loop can feed what the observer reads.
    private var disconnectedStream: AsyncStream<String>?
    private var disconnectedContinuation: AsyncStream<String>.Continuation?
    /// Set by close() so the recv loop's resulting receive() error is recognized as an intentional shutdown and does NOT emit a `disconnected` (which would trigger a pointless reconnect after a user-initiated end).
    private var isClosing = false

    // Ready-state gating. Unlike PersonaPlex (which sends a `\x00` handshake byte), OpenAI Realtime's server is warm from the moment we receive the first `session.created` event. We track that event as the "ready" signal so the audio pump unblocks predictably.
    private var ready = false
    private var readyWaiters: [CheckedContinuation<Void, Never>] = []

    /// First-event wall-clock for relative-time diagnostics. Set lazily on first event so logs show `t=…ms` rather than absolute timestamps — easier to read the ordering between `response.output_audio.delta` and `conversation.item.input_audio_transcription.completed`.
    private var firstEventAt: Date?

    /// Token usage summed across every `response.done` in the session. SessionController reads this at end and reports it to the backend for cost analysis.
    private var usageAcc = RealtimeUsage.zero
    var usage: RealtimeUsage {
        usageAcc
    }

    /// Persona prompt to push via `session.update` after the WS opens. Captured in the initializer because the OpenAI Realtime protocol requires the client to send instructions on every new session (the ephemeral token doesn't carry them).
    private let instructions: String?

    init(instructions: String? = nil) {
        // Ephemeral session avoids TLS resumption issues across rapid reconnects, same reasoning as PersonaPlexClient.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 600
        config.timeoutIntervalForResource = 3600
        session = URLSession(configuration: config)
        self.instructions = instructions
    }

    nonisolated var inboundAudio: AsyncStream<Data> {
        get async { await audioStreamMaybeInit() }
    }

    nonisolated var transcript: AsyncStream<TranscriptChunk> {
        get async { await transcriptStreamMaybeInit() }
    }

    nonisolated var errors: AsyncStream<String> {
        get async { await errorStreamMaybeInit() }
    }

    nonisolated var bargeIn: AsyncStream<Void> {
        get async { await bargeInStreamMaybeInit() }
    }

    nonisolated var toolCalls: AsyncStream<ToolCall> {
        get async { await toolCallStreamMaybeInit() }
    }

    nonisolated var disconnected: AsyncStream<String> {
        get async { await disconnectedStreamMaybeInit() }
    }

    private func audioStreamMaybeInit() -> AsyncStream<Data> {
        if let existing = audioStream { return existing }
        let s = AsyncStream<Data> { continuation in
            self.audioContinuation = continuation
        }
        audioStream = s
        return s
    }

    private func transcriptStreamMaybeInit() -> AsyncStream<TranscriptChunk> {
        if let existing = transcriptStream { return existing }
        let s = AsyncStream<TranscriptChunk> { continuation in
            self.transcriptContinuation = continuation
        }
        transcriptStream = s
        return s
    }

    private func errorStreamMaybeInit() -> AsyncStream<String> {
        if let existing = errorStream { return existing }
        let s = AsyncStream<String> { continuation in
            self.errorContinuation = continuation
        }
        errorStream = s
        return s
    }

    private func disconnectedStreamMaybeInit() -> AsyncStream<String> {
        if let existing = disconnectedStream { return existing }
        let s = AsyncStream<String> { continuation in
            self.disconnectedContinuation = continuation
        }
        disconnectedStream = s
        return s
    }

    private func bargeInStreamMaybeInit() -> AsyncStream<Void> {
        if let existing = bargeInStream { return existing }
        let s = AsyncStream<Void> { continuation in
            self.bargeInContinuation = continuation
        }
        bargeInStream = s
        return s
    }

    private func toolCallStreamMaybeInit() -> AsyncStream<ToolCall> {
        if let existing = toolCallStream { return existing }
        let s = AsyncStream<ToolCall> { continuation in
            self.toolCallContinuation = continuation
        }
        toolCallStream = s
        return s
    }

    func waitForServerReady() async {
        if ready { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            readyWaiters.append(continuation)
        }
    }

    private func signalReady() {
        guard !ready else { return }
        ready = true
        let waiters = readyWaiters
        readyWaiters.removeAll()
        for w in waiters {
            w.resume()
        }
        // Trigger the AI's opening turn. OpenAI Realtime won't generate audio until the client sends `response.create` (or the user sends audio that triggers VAD). Per product spec, the persona should open the conversation in character — so we kick the response immediately after session.created.
        Task { try? await triggerResponse() }
    }

    private func triggerResponse() async throws {
        guard let task else { return }
        let payload = ["type": "response.create"]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard let json = String(data: data, encoding: .utf8) else { return }
        try await task.send(.string(json))
        logger.error("OpenAI WS sent response.create")
    }

    /// Inject a system hint into the live conversation and trigger the AI to respond. Used by SessionController's free-cap wrap-up: 30s before the user's daily/weekly limit is exhausted, we send a system message telling the persona to wind down naturally so the user hears a real goodbye instead of getting cut off mid-sentence.
    func injectSystemHint(_ text: String) async {
        guard let task else { return }
        let item: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "system",
                "content": [["type": "input_text", "text": text]],
            ],
        ]
        let create: [String: Any] = ["type": "response.create"]
        do {
            for payload in [item, create] {
                let data = try JSONSerialization.data(withJSONObject: payload, options: [])
                guard let json = String(data: data, encoding: .utf8) else { continue }
                try await task.send(.string(json))
            }
            logger.error("OpenAI WS sent wrap-up system hint")
        } catch {
            logger.error("OpenAI WS wrap-up hint failed: \(String(describing: error), privacy: .public)")
        }
    }

    func open(wsUrl: String, ephemeralToken: String?) async throws {
        guard let token = ephemeralToken, !token.isEmpty else {
            throw OpenAIRealtimeError.missingEphemeralToken
        }
        guard let url = URL(string: wsUrl) else { throw OpenAIRealtimeError.invalidURL }

        _ = audioStreamMaybeInit()
        _ = transcriptStreamMaybeInit()
        _ = errorStreamMaybeInit()

        var request = URLRequest(url: url)
        // Authorization carries the short-lived (~10 min default TTL) client_secret minted by the backend via
        // /v1/realtime/client_secrets. The WS upgrade re-validates it once; long-running sessions stay alive on the
        // /upgraded connection without re-auth. No `OpenAI-Beta` header — the Realtime API moved to GA and the Beta
        // /shape is rejected (`beta_api_shape_disabled`).
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        // Promoted to .error temporarily so it surfaces in `idevicesyslog` — only error-level events show on device.
        // Drop back to .info once the eternal-loading bug is closed.
        logger.error("OpenAI WS opened url=\(url.absoluteString, privacy: .public)")

        // No client-side session.update — backend already configured the session (instructions, voice, audio formats)
        // when minting the client_secret. session.created fires automatically as the first server event on connect.

        Task { await self.readLoop() }
    }

    /// One frame of raw PCM16 (24kHz mono little-endian Int16) bytes. `AudioStreamer` is responsible for the
    /// Float32→Int16 conversion before calling this.
    func send(audio chunk: Data) async throws {
        guard let task else { throw OpenAIRealtimeError.notConnected }
        let base64 = chunk.base64EncodedString()
        let payload: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard let json = String(data: data, encoding: .utf8) else { return }
        try await task.send(.string(json))
    }

    func close() async {
        isClosing = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        audioContinuation?.finish()
        transcriptContinuation?.finish()
        errorContinuation?.finish()
        toolCallContinuation?.finish()
        disconnectedContinuation?.finish()
        // Resume anyone still parked in waitForServerReady() — e.g. a session closed (timeout/teardown) before `session.created` arrived. Without this the continuation leaks. Callers race this against a timeout, so a late resume here is ignored.
        let waiters = readyWaiters
        readyWaiters.removeAll()
        for w in waiters {
            w.resume()
        }
    }

    private func readLoop() async {
        guard let task else { return }
        while task.closeCode == .invalid {
            do {
                let message = try await task.receive()
                switch message {
                case let .data(data):
                    handleEvent(data: data)
                case let .string(text):
                    if let data = text.data(using: .utf8) {
                        handleEvent(data: data)
                    }
                @unknown default:
                    continue
                }
            } catch {
                logger.error("OpenAI WS recv loop exit: \(String(describing: error), privacy: .public)")
                // A clean close() throws here too (cancelled receive) — only an UNEXPECTED exit is a recoverable disconnect worth reconnecting from.
                if !isClosing { disconnectedContinuation?.yield(String(describing: error)) }
                break
            }
        }
        audioContinuation?.finish()
        transcriptContinuation?.finish()
        errorContinuation?.finish()
        disconnectedContinuation?.finish()
    }

    /// Visible to the test bundle so we can feed synthetic JSON event frames at the unit-test layer without spinning up a real WebSocket. Production callers go through `readLoop()` which receives from the WS task and forwards into this method.
    func handleEvent(data: Data) {
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = parsed["type"] as? String
        else { return }
        // Diagnostic — every event type the server emits, with relative ms-since-first-event so we can see the ordering between user-audio commit → audio.delta → transcription.completed at a glance.
        if firstEventAt == nil { firstEventAt = Date() }
        let tMs = Int(Date().timeIntervalSince(firstEventAt!) * 1000)
        if type == "error" {
            let body = String(data: data, encoding: .utf8) ?? "?"
            logger.error("OpenAI WS [t=\(tMs, privacy: .public)ms] error body=\(body, privacy: .public)")
        } else {
            logger.error("OpenAI WS [t=\(tMs, privacy: .public)ms] evt type=\(type, privacy: .public)")
        }
        if type == "input_audio_buffer.speech_started" {
            bargeInContinuation?.yield(())
        }
        switch type {
        case "session.created", "session.updated":
            signalReady()
        case "response.output_audio.delta":
            if let b64 = parsed["delta"] as? String, let bytes = Data(base64Encoded: b64) {
                audioContinuation?.yield(bytes)
            }
        case "response.output_audio_transcript.delta":
            if let delta = parsed["delta"] as? String, !delta.isEmpty {
                transcriptContinuation?.yield(.init(speaker: .persona, text: delta))
            }
        case "conversation.item.input_audio_transcription.completed":
            if let transcriptText = parsed["transcript"] as? String, !transcriptText.isEmpty {
                transcriptContinuation?.yield(.init(speaker: .user, text: transcriptText))
            }
        case "response.done":
            accumulateUsage(from: parsed)
        case "response.function_call_arguments.done":
            yieldToolCall(from: parsed)
        case "error":
            let nested = parsed["error"] as? [String: Any]
            let message = (nested?["message"] as? String)
                ?? (parsed["message"] as? String)
                ?? "unknown error"
            errorContinuation?.yield(message)
        default:
            break
        }
    }

    /// Parse a `response.function_call_arguments.done` event and forward it as a `ToolCall`. arguments is a JSON string like {"query":"..."}. Split out of `handleEvent` to keep that switch under SwiftLint's complexity budget.
    /// Sum the token usage from one `response.done`. OpenAI reports per-response totals under `response.usage`; the session total is the sum across responses.
    private func accumulateUsage(from parsed: [String: Any]) {
        let delta = Self.usageDelta(from: parsed)
        usageAcc.inputTokens += delta.inputTokens
        usageAcc.outputTokens += delta.outputTokens
    }

    /// One `response.done`'s token usage, or `.zero` if the event lacks a usage block. Static + pure so the parsing is unit-testable without a live WS (a malformed event must contribute 0, never corrupt the running total).
    static func usageDelta(from parsed: [String: Any]) -> RealtimeUsage {
        guard let response = parsed["response"] as? [String: Any],
              let usage = response["usage"] as? [String: Any]
        else { return .zero }
        return RealtimeUsage(
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
        )
    }

    private func yieldToolCall(from parsed: [String: Any]) {
        guard let callId = parsed["call_id"] as? String, let name = parsed["name"] as? String else {
            return
        }
        let argsString = parsed["arguments"] as? String ?? "{}"
        var query = ""
        if let argsData = argsString.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]
        {
            // web_fetch passes "url"; recall tools pass "query". Either is the tool's single argument.
            query = (obj["query"] as? String) ?? (obj["url"] as? String) ?? ""
        }
        toolCallContinuation?.yield(ToolCall(callId: callId, name: name, query: query))
    }

    /// Return a tool result to the model and let it continue: a `function_call_output` item carrying the result, then `response.create`. Sent as a separate async step from the audio pump, so a slow recall never stalls playback — the model keeps talking and weaves the result in when it lands.
    func submitToolOutput(callId: String, output: String) async {
        guard let task else { return }
        let item: [String: Any] = [
            "type": "conversation.item.create",
            "item": ["type": "function_call_output", "call_id": callId, "output": output],
        ]
        let create: [String: Any] = ["type": "response.create"]
        for payload in [item, create] {
            guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
                  let json = String(data: data, encoding: .utf8)
            else { continue }
            try? await task.send(.string(json))
        }
    }
}
