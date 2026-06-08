import Foundation
import OSLog

private let signposter = OSSignposter(subsystem: "com.palkietalkie", category: "personaplex")
private let logger = Logger(subsystem: "com.palkietalkie", category: "personaplex")

struct TranscriptChunk: Identifiable {
    let id: UUID
    enum Speaker: String { case user, persona }
    let speaker: Speaker
    let text: String
    let timestamp: Date

    init(speaker: Speaker, text: String, timestamp: Date = Date()) {
        id = UUID()
        self.speaker = speaker
        self.text = text
        self.timestamp = timestamp
    }
}

enum PersonaPlexError: Error {
    case invalidURL
    case socketClosed(URLSessionWebSocketTask.CloseCode)
    case decoding(Error)
    case notConnected
}

/// Parsed binary frame from the PersonaPlex wire protocol. Pure value type so frame parsing is unit-testable without
/// spinning up a WebSocket.
enum PersonaPlexFrame: Equatable {
    case handshake(version: UInt8, model: UInt8)
    case audio(Data)
    case text(String)
    case control(PersonaPlexClient.ControlAction)
    case metadata(Data)
    case error(String)
    case ping
}

/// PersonaPlex wire format (canonical NVIDIA binary protocol).
///
/// Each binary frame is `[type_byte, ...payload]`:
///   0x00 handshake    `[0x00, version_byte, model_byte]` — client → server, sent first.
///   0x01 audio        `[0x01, ...opus_bytes]` — bidirectional. Opus 24kHz mono 20ms VoIP.
///   0x02 text         `[0x02, ...utf8]` — server → client transcript chunks.
///   0x03 control      `[0x03, action_byte]` — start=0, endTurn=1, pause=2, restart=3.
///   0x04 metadata     `[0x04, ...json_utf8]` — server info / model metadata.
///   0x05 error        `[0x05, ...utf8]` — server-side error string.
///   0x06 ping         `[0x06]` — keep-alive. Client auto-responds with the same frame.
actor PersonaPlexClient {
    enum FrameType: UInt8 {
        case handshake = 0x00
        case audio = 0x01
        case text = 0x02
        case control = 0x03
        case metadata = 0x04
        case error = 0x05
        case ping = 0x06
    }

    enum ControlAction: UInt8 {
        case start = 0
        case endTurn = 1
        case pause = 2
        case restart = 3
    }

    // MARK: - Pure frame codec (unit-testable without a WebSocket)

    static func decodeFrame(_ frame: Data) -> PersonaPlexFrame? {
        guard let first = frame.first, let type = FrameType(rawValue: first) else { return nil }
        let payload = frame.dropFirst()
        return decodePayload(type: type, payload: payload)
    }

    private static func decodePayload(type: FrameType, payload: Data) -> PersonaPlexFrame? {
        switch type {
        case .handshake: decodeHandshakePayload(payload)
        case .audio: .audio(Data(payload))
        case .text: decodeTextPayload(payload).map(PersonaPlexFrame.text)
        case .control: decodeControlPayload(payload).map(PersonaPlexFrame.control)
        case .metadata: .metadata(Data(payload))
        case .error: decodeTextPayload(payload).map(PersonaPlexFrame.error)
        case .ping: .ping
        }
    }

    private static func decodeHandshakePayload(_ payload: Data) -> PersonaPlexFrame {
        // Server may echo a 1-byte handshake; tolerate any length up to 3.
        let version = payload.count > 0 ? payload[payload.startIndex] : 0
        let model = payload.count > 1 ? payload[payload.index(after: payload.startIndex)] : 0
        return .handshake(version: version, model: model)
    }

    private static func decodeTextPayload(_ payload: Data) -> String? {
        String(data: payload, encoding: .utf8)
    }

    private static func decodeControlPayload(_ payload: Data) -> ControlAction? {
        guard let raw = payload.first else { return nil }
        return ControlAction(rawValue: raw)
    }

    static func encodeHandshake(version: UInt8 = 0, model: UInt8 = 0) -> Data {
        Data([FrameType.handshake.rawValue, version, model])
    }

    static func encodeAudio(_ opusFrame: Data) -> Data {
        var frame = Data(capacity: opusFrame.count + 1)
        frame.append(FrameType.audio.rawValue)
        frame.append(opusFrame)
        return frame
    }

    static func encodeControl(_ action: ControlAction) -> Data {
        Data([FrameType.control.rawValue, action.rawValue])
    }

    static func encodePing() -> Data {
        Data([FrameType.ping.rawValue])
    }

    // MARK: - WebSocket lifecycle

    private var task: URLSessionWebSocketTask?
    private let session: URLSession

    private var transcriptStream: AsyncStream<TranscriptChunk>?
    private var transcriptContinuation: AsyncStream<TranscriptChunk>.Continuation?
    private var audioStream: AsyncStream<Data>?
    private var audioContinuation: AsyncStream<Data>.Continuation?
    private var metadataStream: AsyncStream<Data>?
    private var metadataContinuation: AsyncStream<Data>.Continuation?
    private var errorStream: AsyncStream<String>?
    private var errorContinuation: AsyncStream<String>.Continuation?

    // Set true the first time the server sends its handshake byte (0x00). The audio pump must NOT start until this is
    // true: the server's recv_loop only starts after step_system_prompts_async (~30s on cold start). If we send audio before that, the bytes either get buffered out of order or dropped, and sphn's stream decoder fails because the OpusHead pages arrived too early.
    private var handshakeReceived = false
    private var handshakeWaiters: [CheckedContinuation<Void, Never>] = []

    init() {
        // Ephemeral session = no on-disk cache, no cookie store, NO TLS session resumption. Required for our use case:
        // every conversation start creates a fresh WS. With `.default`, iOS caches the TLS session from a previous
        // successful connection and tries to resume it on the next attempt. When Modal's container has scaled down or
        // restarted, server rejects the resumption ticket — Secure Transport closes the connection with `-9816
        // errSSLProtocol` ("TLS protocol error") before our code sees any HTTP. Ephemeral side-steps that by forcing a
        // full TLS handshake every time. We also lose nothing because nothing on the WS path needs caching.
        let config = URLSessionConfiguration.ephemeral
        // Large but bounded timeouts. `greatestFiniteMagnitude` (~1.8e308) made CFNetwork's internal timer math
        // unreliable. 1 hour resource cap covers any real conversation; 10-minute request idle covers Modal cold start
        // (15-30s) with headroom.
        config.timeoutIntervalForRequest = 600
        config.timeoutIntervalForResource = 3600
        session = URLSession(configuration: config)
    }

    var transcript: AsyncStream<TranscriptChunk> {
        if let existing = transcriptStream { return existing }
        let stream = AsyncStream<TranscriptChunk> { continuation in
            self.transcriptContinuation = continuation
        }
        transcriptStream = stream
        return stream
    }

    var inboundAudio: AsyncStream<Data> {
        if let existing = audioStream { return existing }
        let stream = AsyncStream<Data> { continuation in
            self.audioContinuation = continuation
        }
        audioStream = stream
        return stream
    }

    /// Raw JSON bytes of `0x04` metadata frames — caller decodes as needed.
    /// Stays `Data` because `[String: Any]` is not Sendable under Swift 6 strict concurrency.
    var metadata: AsyncStream<Data> {
        if let existing = metadataStream { return existing }
        let stream = AsyncStream<Data> { continuation in
            self.metadataContinuation = continuation
        }
        metadataStream = stream
        return stream
    }

    var errors: AsyncStream<String> {
        if let existing = errorStream { return existing }
        let stream = AsyncStream<String> { continuation in
            self.errorContinuation = continuation
        }
        errorStream = stream
        return stream
    }

    /// Resolve once the server has sent its handshake byte. Audio pump must await this before sending any audio frames.
    func waitForServerHandshake() async {
        if handshakeReceived { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            handshakeWaiters.append(continuation)
        }
    }

    private func signalHandshake() {
        guard !handshakeReceived else { return }
        handshakeReceived = true
        let waiters = handshakeWaiters
        handshakeWaiters.removeAll()
        for w in waiters {
            w.resume()
        }
    }

    /// Opens the WebSocket to PersonaPlex and sends the binary handshake frame.
    ///
    /// Backend (`POST /conversation/start`) returns a fully-built `ws_url` that already includes `text_prompt`,
    /// `voice_prompt`, `auth_token`, and sampling defaults as query params. Open it as-is — no client-side URL
    /// construction.
    func connect(wsUrl: String) async throws {
        // Touch streams so continuations are wired before the read loop starts.
        _ = transcript
        _ = inboundAudio
        _ = metadata
        _ = errors

        guard let url = URL(string: wsUrl) else { throw PersonaPlexError.invalidURL }

        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()

        try await task.send(.data(Self.encodeHandshake()))
        logger.info("WS opened, client handshake sent to \(url.host ?? "?", privacy: .public)")

        Task { await self.readLoop() }
    }

    private var sendCount = 0

    /// Sends one Opus frame (24kHz mono 20ms VoIP) prefixed with the audio tag byte.
    func sendAudio(_ opusFrame: Data) async throws {
        guard let task else { throw PersonaPlexError.notConnected }
        sendCount += 1
        if sendCount <= 3 || sendCount % 50 == 0 {
            logger
                .info(
                    "WS send audio frame #\(self.sendCount, privacy: .public), \(opusFrame.count + 1, privacy: .public) bytes",
                )
        }
        try await task.send(.data(Self.encodeAudio(opusFrame)))
    }

    func sendControl(_ action: ControlAction) async throws {
        guard let task else { throw PersonaPlexError.notConnected }
        try await task.send(.data(Self.encodeControl(action)))
    }

    /// Convenience for the caller's "I'm done" signal — sends control(endTurn).
    func endTurn() async throws {
        try await sendControl(.endTurn)
    }

    func close() async {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        transcriptContinuation?.finish()
        audioContinuation?.finish()
        metadataContinuation?.finish()
        errorContinuation?.finish()
    }

    private func readLoop() async {
        guard let task else { return }
        var frameCount = 0
        while task.closeCode == .invalid {
            do {
                let message = try await task.receive()
                frameCount += 1
                if frameCount <= 3 || frameCount % 50 == 0 {
                    logger
                        .info(
                            "WS recv frame #\(frameCount, privacy: .public), type=\(String(describing: message), privacy: .public)",
                        )
                }
                switch message {
                case let .data(data):
                    dispatchFrame(data)
                case let .string(text):
                    // Server should send binary; tolerate string frames as metadata payloads.
                    if let data = text.data(using: .utf8) {
                        metadataContinuation?.yield(data)
                    }
                @unknown default:
                    continue
                }
            } catch {
                logger
                    .error(
                        "WS recv loop exit at frame #\(frameCount, privacy: .public), error: \(String(describing: error), privacy: .public), closeCode: \(task.closeCode.rawValue, privacy: .public)",
                    )
                break
            }
        }
        transcriptContinuation?.finish()
        audioContinuation?.finish()
        metadataContinuation?.finish()
        errorContinuation?.finish()
    }

    /// Internal so the test bundle can feed synthetic frames at the unit-test layer. Production goes through
    /// `readLoop()` which receives frames from the WebSocket task and forwards them here.
    func dispatchFrame(_ frame: Data) {
        guard let parsed = Self.decodeFrame(frame) else { return }
        switch parsed {
        case .handshake:
            // Server is ready — unblock anyone awaiting `waitForServerHandshake()` (the audio pump).
            signalHandshake()
            logger.info("server handshake byte received; audio pump unblocked")
        case let .audio(data):
            audioContinuation?.yield(data)
        case let .text(text):
            transcriptContinuation?.yield(.init(speaker: .persona, text: text))
        case .control:
            // Server-originated control frames not used yet; ignore.
            break
        case let .metadata(data):
            metadataContinuation?.yield(data)
        case let .error(text):
            errorContinuation?.yield(text)
        case .ping:
            Task { await self.respondPong() }
        }
    }

    private func respondPong() async {
        guard let task else { return }
        // Pong is the same single-byte frame back at the server.
        try? await task.send(.data(Self.encodePing()))
    }
}
