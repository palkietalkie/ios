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
/// We do NOT speak the binary Ogg-Opus protocol PersonaPlex uses. Caller passes raw PCM16 little-endian to
/// `send(audio:)`; we base64-encode and wrap in the JSON event. `inboundAudio` yields raw PCM16 chunks for the speaker
/// side.
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

    // Ready-state gating. Unlike PersonaPlex (which sends a `\x00` handshake byte), OpenAI Realtime's server is warm
    // from the moment we receive the first `session.created` event. We track that event as the "ready" signal so the
    // audio pump unblocks predictably.
    private var ready = false
    private var readyWaiters: [CheckedContinuation<Void, Never>] = []

    /// Persona prompt to push via `session.update` after the WS opens. Captured in the initializer because the OpenAI
    /// Realtime protocol requires the client to send instructions on every new session (the ephemeral token doesn't
    /// carry them).
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

    private func bargeInStreamMaybeInit() -> AsyncStream<Void> {
        if let existing = bargeInStream { return existing }
        let s = AsyncStream<Void> { continuation in
            self.bargeInContinuation = continuation
        }
        bargeInStream = s
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
        // Trigger the AI's opening turn. OpenAI Realtime won't generate audio until the client sends `response.create`
        // (or the user sends audio that triggers VAD). Per product spec, the persona should open the conversation in
        // character — so we kick the response immediately after session.created.
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
            "audio": base64
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard let json = String(data: data, encoding: .utf8) else { return }
        try await task.send(.string(json))
    }

    func close() async {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        audioContinuation?.finish()
        transcriptContinuation?.finish()
        errorContinuation?.finish()
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
                break
            }
        }
        audioContinuation?.finish()
        transcriptContinuation?.finish()
        errorContinuation?.finish()
    }

    private func handleEvent(data: Data) {
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = parsed["type"] as? String
        else { return }
        // Diagnostic — every event type the server emits. Surfaces on device via .error.
        if type == "error" {
            let body = String(data: data, encoding: .utf8) ?? "?"
            logger.error("OpenAI WS error body=\(body, privacy: .public)")
        } else {
            logger.error("OpenAI WS evt type=\(type, privacy: .public)")
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
}
