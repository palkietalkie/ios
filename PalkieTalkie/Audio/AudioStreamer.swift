// AudioStreamer owns the full AVAudioEngine lifecycle (mic tap → encode, decode → playerNode, barge-in, AEC, route changes). The audio-graph state machine stays atomic on purpose — see CLAUDE.md "AVAudioEngine stays running at all times" and the historical SRP-split failure note below.
@preconcurrency import AVFoundation
import Foundation
import Opus
import OSLog

private let signposter = OSSignposter(subsystem: "com.palkietalkie", category: "audio")
private let logger = Logger(subsystem: "com.palkietalkie", category: "audio")

enum AudioStreamerError: Error {
    case engineStartFailed(Error)
    case formatUnavailable
    case opusInitFailed(Error)
}

/// Full-duplex Opus pipe over a running AVAudioEngine. Engine stays up for the entire app lifetime. Actor-isolated because mic-tap callbacks and WebSocket consumers race otherwise.
///
/// History: SRP split into AudioCapture + AudioPlayback was attempted and broke audio (sessions opened, server sent handshake, then iOS closed WS without sending any frames). Mic and speaker share the AVAudioEngine + AVAudioSession lifecycle; splitting those gained nothing concrete and lost working audio. The pure-math helpers (AudioMath) and the wav recorder (WavAudioRecorder) have since been extracted — those don't touch the engine state machine.
actor AudioStreamer {
    static let sampleRate: Double = 24000
    static let frameSamples: AVAudioFrameCount = 480 // 20ms @ 24kHz

    /// Noise-gate cutoff in dBFS. Frames quieter than this get zeroed before encoding so OpenAI's server VAD doesn't trip on room tone. -45 ≈ between room tone (-50) and a whisper (-35). Tunable per real-world data.
    static let noiseGateDbfs: Float = -45

    private let engine: AudioEngineProtocol
    private let playerNode: AudioPlayerNodeProtocol

    init(
        engine: AudioEngineProtocol = RealAudioEngine(),
        playerNode: AudioPlayerNodeProtocol = RealAudioPlayerNode(),
    ) {
        self.engine = engine
        self.playerNode = playerNode
    }

    private var encoder: Opus.Encoder?
    private var decoder: Opus.Decoder?
    /// Cached at start() so playPCM16 reuses the exact same AVAudioFormat instance that was passed to engine.connect. Two structurally-equivalent AVAudioFormat instances are NOT always treated as equal by AVAudioEngine — using a different instance can silently trigger an internal converter that drops audio.
    private var playbackFormat: AVAudioFormat?
    /// Wraps each raw Opus packet in an Ogg page so the server's `sphn.OpusStreamReader` (which expects ogg/opus bytes) can decode our stream.
    private var oggWriter: OggOpusWriter?
    /// Inverse direction: server emits Ogg-Opus pages via `sphn.OpusStreamWriter`. We demux them into raw Opus packets before feeding `swift-opus.Decoder.decode(_:)`.
    private var oggReader: OggOpusReader?

    /// Mic-side PCM16 recorder. Each 20ms frame the encoder receives also lands here. On stop() the URL is exposed via `recordedSessionAudioURL` so SessionController can gzip + upload + delete.
    private let sessionAudioRecorder = WavAudioRecorder(prefix: "session", sampleRate: UInt32(AudioStreamer.sampleRate))
    /// Mirror for the AI's RAW PCM16 output as it arrives from the realtime model — written from `playPCM16` BEFORE any iOS playback DSP touches the bytes. Lets us compare the model's raw stream to what the user perceived and pinpoint truncation between the two.
    private let modelAudioRecorder = WavAudioRecorder(prefix: "model", sampleRate: UInt32(AudioStreamer.sampleRate))
    /// The 0-or-1 leftover byte from the previous OpenAI audio chunk that didn't complete a 2-byte sample; prepended to the next chunk so a sample straddling the boundary isn't dropped. `Data()` = empty = nothing carried. See JARGON: PCM16 (streaming note) and Data. Reset at start().
    private var pcm16Carry = Data()

    /// URL of the wav file containing the user-side audio from the most-recently-finished session. Cleared on next start(). Returned for upload + local cleanup by SessionController.end(). Nil if no session has finished yet.
    var recordedSessionAudioURL: URL? {
        sessionAudioRecorder.url
    }

    var recordedModelAudioURL: URL? {
        modelAudioRecorder.url
    }

    private var inputContinuation: AsyncStream<Data>.Continuation?
    private var inputStreamCache: AsyncStream<Data>?
    private var pcm16InputContinuation: AsyncStream<Data>.Continuation?
    private var pcm16InputStreamCache: AsyncStream<Data>?
    private var pendingMicSamples: [Float] = []
    nonisolated let pitchTracker = PitchTracker()

    private(set) var isRunning = false

    var inputChunks: AsyncStream<Data> {
        if let existing = inputStreamCache { return existing }
        let stream = AsyncStream<Data> { continuation in
            self.inputContinuation = continuation
        }
        inputStreamCache = stream
        return stream
    }

    /// Raw PCM16 (24kHz mono little-endian Int16) frames per 20ms tick. Parallel to `inputChunks` (Ogg-Opus). The OpenAI Realtime path consumes this; PersonaPlex stays on the Opus path.
    var pcm16InputChunks: AsyncStream<Data> {
        if let existing = pcm16InputStreamCache { return existing }
        let stream = AsyncStream<Data> { continuation in
            self.pcm16InputContinuation = continuation
        }
        pcm16InputStreamCache = stream
        return stream
    }

    func start() throws {
        guard !isRunning else { return }
        let state = signposter.beginInterval("audio.start")
        defer { signposter.endInterval("audio.start", state) }

        let opusFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false,
        )!
        playbackFormat = opusFormat

        do {
            encoder = try Opus.Encoder(format: opusFormat, application: .voip)
            decoder = try Opus.Decoder(format: opusFormat)
        } catch {
            throw AudioStreamerError.opusInitFailed(error)
        }
        oggWriter = OggOpusWriter(sampleRate: UInt32(Self.sampleRate), channels: 1)
        oggReader = OggOpusReader()

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: opusFormat)
        // Make sure both mixer stages are at unity gain. They default to 1.0 but be explicit — a 0.5 anywhere multiplies through and quietly halves the audible volume.
        playerNode.volume = 1.0
        engine.mainMixerNode.outputVolume = 1.0
        // No `overrideOutputAudioPort(.speaker)` here — that forces the bottom speaker even when AirPods are connected, breaking the AirPods route. AudioSession.configureForFullDuplexVoice uses `.defaultToSpeaker` which means "bottom speaker when no headphones, AirPods/wired when connected" — the behavior every other media app has.

        let inputNode = engine.inputNode
        // Enable AEC surgically on the mic input (and only the mic), instead of via `.videoChat` session mode which gates output. Without this, the AI's speaker output bleeds into the mic and gets transcribed as if the user said it. Must be called BEFORE `inputFormat(forBus:)` and engine.start so the format reflects the voice-processed unit.
        do {
            try inputNode.setVoiceProcessingEnabled(true)
            // Once voice-processing is enabled, iOS routes the whole audio session through its Voice Processing IO unit, which by default applies automatic-gain-control (with a noise gate) to BOTH input and output. The output-side gate silences sub-threshold audio, which clipped the "s" tail of "Wes" → "We" on this build. Disabling AGC keeps acoustic-echo-cancellation on (the bit we actually need to break the self-echo loop) without the gate that mutes quiet consonants.
            inputNode.isVoiceProcessingAGCEnabled = false
            logger.error("AEC on, AGC off (voiceProcessing=true, AGC=false)")
        } catch {
            logger
                .error(
                    "AEC enable FAILED on mic input — self-echo loop likely: \(String(describing: error), privacy: .public)",
                )
        }
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw AudioStreamerError.formatUnavailable
        }

        // Begin session-audio recording: write PCM16 samples to a temp wav file as they're ingested. SessionController.end() picks this up, gzips, uploads, deletes. 14-day retention server-side; nothing persists on the device past the next session.
        sessionAudioRecorder.open()
        modelAudioRecorder.open()
        pcm16Carry = Data()

        // The tap block must be @Sendable — capture only the actor + raw Float32 bytes. Samples are converted off-actor (in the audio thread) so we never block AVAudio's real-time path.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let samples = AudioMath.copySamples(from: buffer, inputFormat: inputFormat)
            let rate = Float(inputFormat.sampleRate)
            Task { await self.ingestSamples(samples, inputSampleRate: inputFormat.sampleRate) }
            Task { await self.pitchTracker.ingest(samples: samples, sampleRate: rate) }
        }

        engine.prepare()
        do {
            try engine.start()
            playerNode.play()
            isRunning = true
            logger
                .info(
                    "audio engine started; input sampleRate=\(inputFormat.sampleRate, privacy: .public), target=\(Self.sampleRate, privacy: .public)",
                )
            logCurrentRoute()
        } catch {
            throw AudioStreamerError.engineStartFailed(error)
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        engine.stop()
        inputContinuation?.finish()
        inputContinuation = nil
        inputStreamCache = nil
        pcm16InputContinuation?.finish()
        pcm16InputContinuation = nil
        pcm16InputStreamCache = nil
        pendingMicSamples.removeAll()
        oggWriter = nil
        oggReader = nil
        sessionAudioRecorder.close()
        modelAudioRecorder.close()
        isRunning = false
    }

    /// PCM16 playback path for OpenAI Realtime. Server sends raw 24kHz mono little-endian Int16; we convert to Float32, wrap in AVAudioPCMBuffer, schedule on the player node.
    private var playPCM16Count = 0
    func playPCM16(_ pcm16Bytes: Data) async {
        // Capture the raw model PCM16 bytes BEFORE any iOS playback DSP (voice-processing, format conversion, mixer attenuation). This is the ground-truth signal the realtime model emitted; comparing it to what the user perceived isolates where truncation happens.
        modelAudioRecorder.append(pcm16Bytes)
        // Reuse the same AVAudioFormat instance that engine.connect was called with — see playbackFormat declaration.
        guard let format = playbackFormat else { return }
        // Frame across chunk boundaries, carrying any trailing odd byte. A per-chunk `count / 2` drops that byte and byte-shifts every following sample into static until the stream self-realigns.
        let (samples, carry) = AudioMath.framePCM16(carry: pcm16Carry, appending: pcm16Bytes)
        pcm16Carry = carry
        guard !samples.isEmpty else { return }
        // Hearing-safety guard. Realtime audio has shipped corrupt bursts of full-scale white-noise static that pin most samples to the rail; played raw they are an acoustic-trauma risk in earbuds. Drop the chunk — a few ms of silence is imperceptible, a 0 dBFS noise blast is not. The raw bytes are still recorded above for diagnosis.
        if AudioMath.isSaturatedBurst(samples) {
            logger.error(
                "playPCM16 DROPPED corrupt full-scale burst: \(Int(AudioMath.railFraction(samples) * 100), privacy: .public)% of \(samples.count, privacy: .public) samples at rail — protecting hearing",
            )
            return
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count),
        ) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let dst = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { src in
                if let base = src.baseAddress { dst.update(from: base, count: samples.count) }
            }
        }
        playPCM16Count += 1
        let n = playPCM16Count
        if n <= 3 || n % 50 == 0 {
            let p = AudioMath.peakAmplitude(of: buffer)
            logger
                .error(
                    "playPCM16 sched #\(n, privacy: .public): \(pcm16Bytes.count, privacy: .public)B → frames=\(samples.count, privacy: .public) peak=\(p, privacy: .public) engineRunning=\(self.engine.isRunning, privacy: .public) playerPlaying=\(self.playerNode.isPlaying, privacy: .public)",
                )
        }
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    /// Drop everything queued and resume — caller (AudioPump) hooks this to the realtime client's `bargeIn` stream so user-speech-detected stops AI audio mid-sentence. `playerNode.stop()` cancels scheduled buffers; immediately `play()` again so the next AI turn's audio plays without re-entering the start() bring-up.
    func interruptPlayback() {
        playerNode.stop()
        playerNode.play()
    }

    /// Server frames carry Ogg-Opus bytes (encoded by sphn). Demux into raw Opus packets, decode each, schedule for playback. Loudness handled server-side (see `patch_moshi_server.py`).
    private var playOutputCount = 0

    func playOutput(_ oggBytes: Data) async {
        guard let decoder, let oggReader else { return }
        let packets = oggReader.feed(oggBytes)
        for pkt in packets {
            do {
                let pcm = try decoder.decode(pkt)
                // Same hearing-safety guard as the OpenAI path — never schedule a full-scale-static burst.
                if AudioMath.isSaturatedBurst(pcm) {
                    logger.error("playOutput DROPPED corrupt full-scale burst — protecting hearing")
                    continue
                }
                playOutputCount += 1
                if playOutputCount <= 3 || playOutputCount % 100 == 0 {
                    let p = AudioMath.peakAmplitude(of: pcm)
                    logger
                        .info(
                            "playOutput #\(self.playOutputCount, privacy: .public): pkt \(pkt.count, privacy: .public)B → pcm frames=\(pcm.frameLength, privacy: .public) peak=\(p, privacy: .public)",
                        )
                }
                playerNode.scheduleBuffer(pcm, completionHandler: nil)
            } catch {
                logger.error("opus decode failed: \(String(describing: error), privacy: .public)")
                continue
            }
        }
    }

    private func logCurrentRoute() {
        let route = AVAudioSession.sharedInstance().currentRoute
        let outputs = route.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",")
        let sessionVolume = AVAudioSession.sharedInstance().outputVolume
        logger
            .error(
                "audio route → \(outputs, privacy: .public); playerNode.volume=\(self.playerNode.volume, privacy: .public); mainMixer.outputVolume=\(self.engine.mainMixerNode.outputVolume, privacy: .public); session.outputVolume=\(sessionVolume, privacy: .public); sessionCategory=\(AVAudioSession.sharedInstance().category.rawValue, privacy: .public); sessionMode=\(AVAudioSession.sharedInstance().mode.rawValue, privacy: .public)",
            )
    }

    private func ingestSamples(_ samples: [Float], inputSampleRate: Double) async {
        guard let encoder, let opusFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false,
        ) else { return }

        let resampled: [Float] = if abs(inputSampleRate - Self.sampleRate) < 1 {
            samples
        } else {
            AudioMath.linearResample(samples, from: inputSampleRate, to: Self.sampleRate)
        }

        pendingMicSamples.append(contentsOf: resampled)

        let frameLen = Int(Self.frameSamples)
        while pendingMicSamples.count >= frameLen {
            var chunk = Array(pendingMicSamples.prefix(frameLen))
            pendingMicSamples.removeFirst(frameLen)

            // Noise gate: zero out frames whose RMS sits at room-tone level. Cuts the chances of OpenAI's server VAD misfiring on wind / scooter rattle / AirPod-bleed of our own TTS. -45 dBFS is conservative — clear speech runs ~ -20 dBFS, room tone ~ -50 to -45. Adjust upward if false positives persist (raise gate), downward if real soft speech is being eaten (lower gate). AEC + voice processing still apply earlier in the chain; this is the final defense.
            if AudioMath.rmsDbfs(chunk) < Self.noiseGateDbfs {
                for i in chunk.indices {
                    chunk[i] = 0
                }
            }

            // Session audio recording — same PCM16 bytes the OpenAI path emits, but also tee'd to disk for the 14-day debug/abuse window. Computed once so the to-disk + over-the-wire copies match exactly. Built inside the gate-aware branch so silence-gated frames record as silence too (matches what OpenAI sees).
            var pcm16Bytes = Data(count: frameLen * MemoryLayout<Int16>.size)
            pcm16Bytes.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
                guard let dst = raw.bindMemory(to: Int16.self).baseAddress else { return }
                for i in 0 ..< frameLen {
                    let clamped = max(-1.0, min(1.0, chunk[i]))
                    dst[i] = Int16(clamped * 32767.0)
                }
            }
            sessionAudioRecorder.append(pcm16Bytes)

            // PCM16 path for OpenAI Realtime — reuse the bytes already built above.
            pcm16InputContinuation?.yield(pcm16Bytes)

            let frameCapacity = AVAudioFrameCount(frameLen)
            guard let frameBuf = AVAudioPCMBuffer(pcmFormat: opusFormat, frameCapacity: frameCapacity)
            else { continue }
            frameBuf.frameLength = AVAudioFrameCount(frameLen)
            chunk.withUnsafeBufferPointer { src in
                frameBuf.floatChannelData![0].update(from: src.baseAddress!, count: frameLen)
            }

            var packet = Data(count: 1500)
            let encodedSize: Int
            do {
                encodedSize = try encoder.encode(frameBuf, to: &packet)
            } catch {
                continue
            }
            guard encodedSize > 0 else { continue }
            packet.removeSubrange(encodedSize ..< packet.count)

            guard let oggWriter else { continue }
            var oggBytes = oggWriter.buildHeaderBytes()
            let wasFirst = !oggBytes.isEmpty
            oggBytes.append(oggWriter.wrap(opusPacket: packet, pcmSampleCount: UInt64(frameLen)))
            if wasFirst {
                logger.info("ogg headers + first audio page emitted, \(oggBytes.count, privacy: .public) bytes")
            }
            inputContinuation?.yield(oggBytes)
        }
    }
}
