@preconcurrency import AVFoundation
@preconcurrency import Foundation
import os
import OSLog
@preconcurrency import WebRTC

private let logger = Logger(subsystem: "com.palkietalkie", category: "webrtc")

enum OpenAIWebRTCError: Error {
    case missingEphemeralToken
    case handshakeFailed
}

/// OpenAI Realtime over WebRTC (Opus/SRTP/UDP) — the low-bandwidth, loss-tolerant transport for direct mobile audio, replacing the base64-PCM16-over-WebSocket path (OpenAIRealtimeClient). See task #45.
///
/// Architecture note: unlike the WS client, audio does NOT flow through `send(audio:)` / `inboundAudio`. WebRTC carries the mic + tutor audio as media tracks over its own peer connection, so those byte-pipe methods are no-ops here and `AudioPump` is bypassed for this provider. Only the JSON control events (response.create, transcript deltas, speech_started→bargeIn, tool calls, usage) travel — over a WebRTC data channel — reusing the same event shapes the WS client parses.
///
/// Handshake: create an SDP offer, POST it to `POST /v1/realtime/calls?model=…` with the ephemeral token (Content-Type: application/sdp), apply the SDP answer. Opus is negotiated automatically.
///
/// This first cut uses WebRTC's default audio device (its own mic capture + AEC/AGC + jitter buffer). Re-plumbing our custom DSP (near-field gate, output-amplitude waveform, emotion/pitch, wav recording) onto a custom RTCAudioDeviceModule is the follow-on step of #45.
final class OpenAIWebRTCClient: NSObject, RealtimeClient, @unchecked Sendable {
    /// The full OpenAI `/v1/realtime/calls?model=…` URL to POST the SDP offer to. Supplied by the backend in StartResponse.wsUrl (reused: for WS it's the wss:// URL, for WebRTC it's this HTTPS calls URL), so the model + host stay backend-owned.
    private var callsURL: String?

    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?

    private var audioContinuation: AsyncStream<Data>.Continuation?
    private var transcriptContinuation: AsyncStream<TranscriptChunk>.Continuation?
    private var errorContinuation: AsyncStream<String>.Continuation?
    private var disconnectedContinuation: AsyncStream<String>.Continuation?
    private var bargeInContinuation: AsyncStream<Void>.Continuation?
    private var toolCallContinuation: AsyncStream<ToolCall>.Continuation?

    private var readyContinuation: CheckedContinuation<Void, Never>?
    private var isReady = false
    private var usageValue = RealtimeUsage.zero

    /// Aggregates transcript deltas per speaker turn, mirroring the WS client so CaptionsView renders the same way.
    private var personaTurnBuffer = ""

    /// Stamp of the first event, so each event logs a relative ms offset — makes it visible whether speech_started interrupts an in-flight response (echo → server-VAD → choppy reply).
    private var firstEventAt: Date?

    /// Response lifecycle guard. Read/written from the data-channel callback thread (response.created/done) and the MainActor (injectSystemHint), so it's lock-held.
    private let lifecycle = OSAllocatedUnfairLock(initialState: ResponseLifecycle())

    /// Tutor output amplitude (0…1) for the Talk-view waveform, polled off WebRTC's inbound-audio stats (WebRTC bypasses AudioStreamer, so the level can't come from there). Lock-held: written on the stats-callback queue, read synchronously by the view.
    private let outputLevelLock = OSAllocatedUnfairLock(initialState: Float(0))
    var outputLevel: Float {
        outputLevelLock.withLock { $0 }
    }

    private var levelTimer: DispatchSourceTimer?

    override init() {
        RTCInitializeSSL()
        factory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory(),
        )
        super.init()
    }

    // MARK: RealtimeClient

    func open(wsUrl: String, ephemeralToken: String?) async throws {
        guard let token = ephemeralToken, !token.isEmpty else {
            throw OpenAIWebRTCError.missingEphemeralToken
        }
        callsURL = wsUrl
        configureAudioSession()

        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        let pc = factory.peerConnection(
            with: config,
            constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil),
            delegate: self,
        )
        peerConnection = pc

        // Mic audio track (WebRTC's default capture for now). Send + receive so the tutor's audio plays back.
        let audioSource = factory.audioSource(with: RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil,
        ))
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "mic0")
        pc?.add(audioTrack, streamIds: ["pt0"])

        // Control-event channel (OpenAI sends the same JSON events here that the WS path receives over the socket).
        let dcConfig = RTCDataChannelConfiguration()
        dataChannel = pc?.dataChannel(forLabel: "oai-events", configuration: dcConfig)
        dataChannel?.delegate = self

        let offer = try await makeOffer(pc)
        try await setLocal(pc, offer)
        let answerSDP = try await postOffer(sdp: offer.sdp, token: token)
        try await setRemote(pc, RTCSessionDescription(type: .answer, sdp: answerSDP))
        startLevelPolling()
    }

    func close() async {
        stopLevelPolling()
        dataChannel?.close()
        peerConnection?.close()
        peerConnection = nil
        audioContinuation?.finish()
        transcriptContinuation?.finish()
        errorContinuation?.finish()
        disconnectedContinuation?.finish()
        bargeInContinuation?.finish()
        toolCallContinuation?.finish()
        RTCCleanupSSL()
    }

    /// No-op: WebRTC carries mic audio as a media track, not app-pushed bytes.
    func send(audio _: Data) async throws {}

    func waitForServerReady() async {
        if isReady { return }
        await withCheckedContinuation { c in readyContinuation = c }
    }

    func injectSystemHint(_ text: String) async {
        sendEvent(["type": "conversation.item.create", "item": [
            "type": "message", "role": "system",
            "content": [["type": "input_text", "text": text]],
        ]])
        // If a reply is in flight, defer this response.create until it finishes (OpenAI rejects a second active response, which would drop the goodbye); onResponseDone fires it then. Otherwise send now.
        if lifecycle.withLock({ $0.onWindDownRequested() }) {
            sendEvent(["type": "response.create"])
        }
    }

    func submitToolOutput(callId: String, output: String) async {
        sendEvent(["type": "conversation.item.create", "item": [
            "type": "function_call_output", "call_id": callId, "output": output,
        ]])
        sendEvent(["type": "response.create"])
    }

    var inboundAudio: AsyncStream<Data> {
        get async { AsyncStream { self.audioContinuation = $0 } }
    }

    var transcript: AsyncStream<TranscriptChunk> {
        get async { AsyncStream { self.transcriptContinuation = $0 } }
    }

    var errors: AsyncStream<String> {
        get async { AsyncStream { self.errorContinuation = $0 } }
    }

    var disconnected: AsyncStream<String> {
        get async { AsyncStream { self.disconnectedContinuation = $0 } }
    }

    var bargeIn: AsyncStream<Void> {
        get async { AsyncStream { self.bargeInContinuation = $0 } }
    }

    var toolCalls: AsyncStream<ToolCall> {
        get async { AsyncStream { self.toolCallContinuation = $0 } }
    }

    var usage: RealtimeUsage {
        get async { usageValue }
    }

    /// Extract the inbound (received tutor) audio level (0…1) from a flattened WebRTC stats report — the "inbound-rtp" audio subreport's `audioLevel`. Pure + testable; 0 when there's no inbound audio track yet or the field is absent.
    static func inboundAudioLevel(fromStats stats: [(type: String, values: [String: Any])]) -> Float {
        for stat in stats where stat.type == "inbound-rtp" {
            if (stat.values["kind"] as? String) == "audio", let level = stat.values["audioLevel"] as? NSNumber {
                return level.floatValue
            }
        }
        return 0
    }
}

// MARK: - SDP handshake + control channel

private extension OpenAIWebRTCClient {
    // coverage:ignore-start: SDP handshake, needs a live RTCPeerConnection + network; not runnable in the unit sim.
    func makeOffer(_ pc: RTCPeerConnection?) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { cont in
            pc?.offer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { sdp, err in
                if let sdp {
                    cont.resume(returning: sdp)
                } else {
                    cont.resume(throwing: err ?? OpenAIWebRTCError.missingEphemeralToken)
                }
            }
        }
    }

    func setLocal(_ pc: RTCPeerConnection?, _ sdp: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc?.setLocalDescription(sdp) { err in if let err { cont.resume(throwing: err) } else { cont.resume() } }
        }
    }

    func setRemote(_ pc: RTCPeerConnection?, _ sdp: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc?.setRemoteDescription(sdp) { err in if let err { cont.resume(throwing: err) } else { cont.resume() } }
        }
    }

    /// POST the SDP offer to OpenAI's realtime calls endpoint; the response body is the SDP answer.
    func postOffer(sdp: String, token: String) async throws -> String {
        guard let urlStr = callsURL,
              let url = URL(string: urlStr) else { throw OpenAIWebRTCError.missingEphemeralToken }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(sdp.utf8)
        return try await retryTransient {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
                  let answer = String(data: data, encoding: .utf8)
            else { throw OpenAIWebRTCError.handshakeFailed }
            return answer
        }
    }

    // coverage:ignore-end

    func sendEvent(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        dataChannel?.sendData(RTCDataBuffer(data: data, isBinary: false))
    }

    func markReady() {
        guard !isReady else { return }
        isReady = true
        readyContinuation?.resume()
        readyContinuation = nil
        // Open the conversation in character without waiting for the user (CLAUDE.md Features #1), matching the old WS path's response.create.
        sendEvent(["type": "response.create"])
    }

    // coverage:ignore-start: AVAudioSession config + peer-stats polling timer, needs real audio hardware.
    /// Let WebRTC own the AVAudioSession (playAndRecord + voiceChat with its bundled AEC/AGC/jitter), since the AudioStreamer that used to configure it is skipped for this provider.
    func configureAudioSession() {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        let config = RTCAudioSessionConfiguration.webRTC()
        config.category = AVAudioSession.Category.playAndRecord.rawValue
        config.categoryOptions = [.defaultToSpeaker, .allowBluetoothHFP]
        config.mode = AVAudioSession.Mode.voiceChat.rawValue
        try? session.setConfiguration(config)
        session.isAudioEnabled = true
        session.unlockForConfiguration()
    }

    /// Poll WebRTC's inbound-audio level ~15Hz to drive the Talk-view waveform — WebRTC bypasses AudioStreamer, so the tutor amplitude has to come from the peer connection's own stats. Stopped in close().
    func startLevelPolling() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.palkietalkie.webrtc.level"))
        timer.schedule(deadline: .now() + 0.066, repeating: 0.066)
        timer.setEventHandler { [weak self] in
            guard let self, let pc = self.peerConnection else { return }
            pc.statistics { report in
                let stats = report.statistics.values.map { (type: $0.type, values: $0.values as [String: Any]) }
                self.outputLevelLock.withLock { $0 = Self.inboundAudioLevel(fromStats: stats) }
            }
        }
        timer.resume()
        levelTimer = timer
    }

    func stopLevelPolling() {
        levelTimer?.cancel()
        levelTimer = nil
    }
    // coverage:ignore-end
}

// MARK: - Event dispatch

// Internal (not private) so unit tests can drive it. Kept in this file rather than a Type+Feature file on purpose: handleEvent mutates the client's private state (continuations, usageValue, lifecycle), and Swift `private` is file-scoped, so a separate file would force all of that to widen to internal. The protocol DECODING lives in the pure, fully-tested parseRealtimeEvent; this only routes a decoded event onto the client's streams.

extension OpenAIWebRTCClient {
    func handleEvent(_ data: Data) {
        guard let event = parseRealtimeEvent(data) else { return }
        if firstEventAt == nil { firstEventAt = Date() }
        let tMs = Int(Date().timeIntervalSince(firstEventAt ?? Date()) * 1000)
        logger.error("webrtc [t=\(tMs, privacy: .public)ms] evt=\(event.logLabel, privacy: .public)")
        switch event {
        case .ready:
            markReady()
        case .responseCreated:
            lifecycle.withLock { $0.onResponseCreated() }
        case let .personaTranscriptDelta(text):
            transcriptContinuation?.yield(.init(speaker: .persona, text: text))
        case let .userTranscript(text):
            transcriptContinuation?.yield(.init(speaker: .user, text: text))
        case .speechStarted:
            bargeInContinuation?.yield(())
        case let .responseDone(delta):
            usageValue = RealtimeUsage(
                inputTokens: usageValue.inputTokens + delta.inputTokens,
                outputTokens: usageValue.outputTokens + delta.outputTokens,
            )
            // Fire the free-cap wind-down that was deferred because this reply was in flight when it was requested.
            if lifecycle.withLock({ $0.onResponseDone() }) { sendEvent(["type": "response.create"]) }
        case let .toolCall(call):
            toolCallContinuation?.yield(call)
        case let .error(message):
            if let message { errorContinuation?.yield(message) } else {
                logger.error("webrtc benign error dropped (active response in progress)")
            }
        }
    }
}

// coverage:ignore-start: WebRTC delegate callbacks, fired by the framework off a live peer connection; not invokable in the unit sim.
extension OpenAIWebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        if newState == .failed || newState == .disconnected || newState == .closed {
            disconnectedContinuation?.yield("ice=\(newState.rawValue)")
        }
    }

    func peerConnection(_: RTCPeerConnection, didChange _: RTCSignalingState) {}
    func peerConnection(_: RTCPeerConnection, didAdd _: RTCMediaStream) {}
    func peerConnection(_: RTCPeerConnection, didRemove _: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_: RTCPeerConnection) {}
    func peerConnection(_: RTCPeerConnection, didChange _: RTCIceGatheringState) {}
    func peerConnection(_: RTCPeerConnection, didGenerate _: RTCIceCandidate) {}
    func peerConnection(_: RTCPeerConnection, didRemove _: [RTCIceCandidate]) {}
    func peerConnection(_: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        dataChannel.delegate = self
        self.dataChannel = dataChannel
    }
}

extension OpenAIWebRTCClient: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_: RTCDataChannel) {}
    func dataChannel(_: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        handleEvent(buffer.data)
    }
}

// coverage:ignore-end
