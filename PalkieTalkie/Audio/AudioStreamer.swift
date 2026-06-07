// swiftlint:disable file_length
// AudioStreamer owns the full AVAudioEngine lifecycle (mic tap → encode, decode → playerNode, barge-in, AEC, route changes). Splitting it would fragment the single audio-graph contract; flagged for a future refactor when the responsibilities can cleanly separate without losing the atomic engine state machine.
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

/// Tiny helpers for building the WAV header (which is little-endian by spec, regardless of host endianness). Inlined here because there's no other consumer in the app.
extension Data {
    init(littleEndian value: some FixedWidthInteger) {
        var v = value.littleEndian
        self = Swift.withUnsafeBytes(of: &v) { Data($0) }
    }

    mutating func append(littleEndian value: some FixedWidthInteger) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}

/// Full-duplex Opus pipe over a running AVAudioEngine. Engine stays up for the entire app lifetime — see CLAUDE.md
/// "AVAudioEngine stays running at all times". Actor-isolated because mic-tap callbacks and WebSocket consumers race
/// otherwise.
///
/// SRP split into AudioCapture + AudioPlayback was attempted and broke audio (sessions opened, server sent handshake,
/// then iOS closed WS without sending any frames). Keeping as monolithic until we have a test that catches the
/// regression. The mic and speaker paths share the AVAudioEngine + AVAudioSession lifecycle; splitting them gained
/// nothing concrete and lost working audio.
actor AudioStreamer { // swiftlint:disable:this type_body_length
    static let sampleRate: Double = 24000
    static let frameSamples: AVAudioFrameCount = 480 // 20ms @ 24kHz

    /// Noise-gate cutoff in dBFS. Frames quieter than this get zeroed before encoding so OpenAI's server VAD doesn't trip on room tone. -45 ≈ between room tone (-50) and a whisper (-35). Tunable per real-world data.
    static let noiseGateDbfs: Float = -45

    /// Root-Mean-Square of a Float32 frame, returned in dBFS (decibels relative to full scale). Returns -∞ for true silence. Used only for the noise gate; not for any decoder math.
    static func rmsDbfs(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -.infinity }
        var sumSq: Float = 0
        for s in samples {
            sumSq += s * s
        }
        let rms = (sumSq / Float(samples.count)).squareRoot()
        guard rms > 0 else { return -.infinity }
        return 20 * log10(rms)
    }

    /// Build a 44-byte WAV (RIFF) header for PCM16 mono at our session sample rate. The two size fields (RIFF chunk size + data chunk size) are placeholders here; close-time fixups patch them with the real counts. Layout per http://soundfile.sapp.org/doc/WaveFormat/.
    static func wavHeaderPCM16Mono(sampleRate: UInt32, numSamples: UInt32) -> Data {
        let byteRate: UInt32 = sampleRate * 1 * 16 / 8 // sampleRate * channels * bitsPerSample/8
        let blockAlign: UInt16 = 1 * 16 / 8
        let dataBytes: UInt32 = numSamples * UInt32(blockAlign)
        let riffSize: UInt32 = 36 + dataBytes
        var header = Data()
        header.append("RIFF".data(using: .ascii)!)
        header.append(littleEndian: riffSize)
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.append(littleEndian: UInt32(16)) // PCM fmt chunk size
        header.append(littleEndian: UInt16(1)) // audio format = PCM
        header.append(littleEndian: UInt16(1)) // channels = 1
        header.append(littleEndian: sampleRate)
        header.append(littleEndian: byteRate)
        header.append(littleEndian: blockAlign)
        header.append(littleEndian: UInt16(16)) // bits per sample
        header.append("data".data(using: .ascii)!)
        header.append(littleEndian: dataBytes)
        return header
    }

    /// Open a fresh wav file in the system temp dir, write a placeholder 44-byte header, and stash the handle. Called from start(); idempotent if a prior session's file wasn't cleaned up — we just overwrite.
    private func openSessionAudioFile() {
        sessionAudioSamplesWritten = 0
        let id = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "session-\(id).wav",
        )
        sessionAudioURL = url
        FileManager.default.createFile(atPath: url.path, contents: nil)
        do {
            let handle = try FileHandle(forWritingTo: url)
            let header = Self.wavHeaderPCM16Mono(sampleRate: UInt32(Self.sampleRate), numSamples: 0)
            try handle.write(contentsOf: header)
            sessionAudioHandle = handle
        } catch {
            logger.error("session audio file open failed: \(String(describing: error), privacy: .public)")
            sessionAudioHandle = nil
            sessionAudioURL = nil
        }
    }

    /// Append one frame's worth of PCM16 bytes to the open wav file. Drops silently on a write failure — recording is best-effort, never blocks the audio path.
    private func appendSessionAudio(_ pcm16: Data) {
        guard let handle = sessionAudioHandle else { return }
        do {
            try handle.write(contentsOf: pcm16)
            sessionAudioSamplesWritten &+= UInt32(pcm16.count / MemoryLayout<Int16>.size)
        } catch {
            logger.error("session audio append failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Patch the wav header's two size fields with the actual sample count, close the handle. Called from stop().
    private func closeSessionAudioFile() {
        guard let handle = sessionAudioHandle else { return }
        let samples = sessionAudioSamplesWritten
        do {
            let dataBytes = UInt32(samples) * UInt32(MemoryLayout<Int16>.size)
            let riffSize = UInt32(36 + dataBytes)
            // Header offsets per WAV RIFF spec: byte 4 = riff size (LE u32), byte 40 = data size (LE u32).
            try handle.seek(toOffset: 4)
            try handle.write(contentsOf: Data(littleEndian: riffSize))
            try handle.seek(toOffset: 40)
            try handle.write(contentsOf: Data(littleEndian: dataBytes))
            try handle.close()
        } catch {
            logger.error("session audio close failed: \(String(describing: error), privacy: .public)")
        }
        sessionAudioHandle = nil
    }

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var encoder: Opus.Encoder?
    private var decoder: Opus.Decoder?
    /// Cached at start() so playPCM16 reuses the exact same AVAudioFormat instance that was passed to engine.connect.
    /// Two structurally-equivalent AVAudioFormat instances are NOT always treated as equal by AVAudioEngine — using a
    /// different instance can silently trigger an internal converter that drops audio.
    private var playbackFormat: AVAudioFormat?
    /// Wraps each raw Opus packet in an Ogg page so the server's `sphn.OpusStreamReader` (which expects ogg/opus bytes)
    /// can decode our stream.
    private var oggWriter: OggOpusWriter?
    /// Inverse direction: server emits Ogg-Opus pages via `sphn.OpusStreamWriter`. We demux them into raw Opus packets
    /// before feeding `swift-opus.Decoder.decode(_:)`.
    private var oggReader: OggOpusReader?

    /// File handle the mic-side PCM16 is appended to during the session. Each 20ms frame the encoder receives also lands here. Header is written at start(); samples appended throughout. On stop(), the handle is closed and the URL is exposed via `recordedSessionAudioURL` so SessionController can gzip + upload + delete.
    private var sessionAudioHandle: FileHandle?
    private var sessionAudioURL: URL?
    /// Count of PCM16 samples written so far, used to fix up the wav header's data-chunk size at close.
    private var sessionAudioSamplesWritten: UInt32 = 0

    /// Mirror file for the AI's RAW PCM16 output as it arrives from the realtime model — written from `playPCM16` BEFORE any iOS playback DSP touches the bytes. Lets us compare the model's raw stream to what the user perceived and pinpoint truncation between the two.
    private var modelAudioHandle: FileHandle?
    private var modelAudioURL: URL?
    private var modelAudioSamplesWritten: UInt32 = 0

    var recordedModelAudioURL: URL? {
        modelAudioURL
    }

    private func openModelAudioFile() {
        modelAudioSamplesWritten = 0
        let id = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "model-\(id).wav",
        )
        modelAudioURL = url
        FileManager.default.createFile(atPath: url.path, contents: nil)
        do {
            let handle = try FileHandle(forWritingTo: url)
            let header = Self.wavHeaderPCM16Mono(sampleRate: UInt32(Self.sampleRate), numSamples: 0)
            try handle.write(contentsOf: header)
            modelAudioHandle = handle
        } catch {
            logger.error("model audio file open failed: \(String(describing: error), privacy: .public)")
            modelAudioHandle = nil
            modelAudioURL = nil
        }
    }

    private func appendModelAudio(_ pcm16: Data) {
        guard let handle = modelAudioHandle else { return }
        do {
            try handle.write(contentsOf: pcm16)
            modelAudioSamplesWritten &+= UInt32(pcm16.count / MemoryLayout<Int16>.size)
        } catch {
            logger.error("model audio append failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func closeModelAudioFile() {
        guard let handle = modelAudioHandle else { return }
        let samples = modelAudioSamplesWritten
        do {
            let dataBytes = UInt32(samples) * UInt32(MemoryLayout<Int16>.size)
            let riffSize = UInt32(36 + dataBytes)
            try handle.seek(toOffset: 4)
            try handle.write(contentsOf: Data(littleEndian: riffSize))
            try handle.seek(toOffset: 40)
            try handle.write(contentsOf: Data(littleEndian: dataBytes))
            try handle.close()
        } catch {
            logger.error("model audio close failed: \(String(describing: error), privacy: .public)")
        }
        modelAudioHandle = nil
    }

    /// URL of the wav file containing the user-side audio from the most-recently-finished session. Cleared on next start().
    /// Returned for upload + local cleanup by SessionController.end(). Nil if no session has finished yet.
    var recordedSessionAudioURL: URL? {
        sessionAudioURL
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

    /// Raw PCM16 (24kHz mono little-endian Int16) frames per 20ms tick. Parallel to `inputChunks` (Ogg-Opus). The
    /// OpenAI Realtime path consumes this; PersonaPlex stays on the Opus path.
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
        // Make sure both mixer stages are at unity gain. They default to 1.0 but be explicit — a 0.5 anywhere
        // multiplies through and quietly halves the audible volume.
        playerNode.volume = 1.0
        engine.mainMixerNode.outputVolume = 1.0
        // No `overrideOutputAudioPort(.speaker)` here — that forces the bottom speaker even when AirPods are connected,
        // breaking the AirPods route. AudioSession.configureForFullDuplexVoice uses `.defaultToSpeaker` which means
        // "bottom speaker when no headphones, AirPods/wired when connected" — the behavior every other media app has.

        let inputNode = engine.inputNode
        // Enable AEC surgically on the mic input (and only the mic), instead of via `.videoChat` session mode which
        // gates output. Without this, the AI's speaker output bleeds into the mic and gets transcribed as if the user
        // said it. Must be called BEFORE `inputFormat(forBus:)` and engine.start so the format reflects the
        // voice-processed unit.
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
        openSessionAudioFile()
        openModelAudioFile()

        // The tap block must be @Sendable — capture only the actor + raw Float32 bytes. Samples are converted off-actor
        // (in the audio thread) so we never block AVAudio's real-time path.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let samples = Self.copySamples(from: buffer, inputFormat: inputFormat)
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
        closeSessionAudioFile()
        closeModelAudioFile()
        isRunning = false
    }

    /// PCM16 playback path for OpenAI Realtime. Server sends raw 24kHz mono little-endian Int16; we convert to Float32,
    /// wrap in AVAudioPCMBuffer, schedule on the player node.
    private var playPCM16Count = 0
    func playPCM16(_ pcm16Bytes: Data) async {
        // Capture the raw model PCM16 bytes BEFORE any iOS playback DSP (voice-processing, format conversion, mixer attenuation). This is the ground-truth signal the realtime model emitted; comparing it to what the user perceived isolates where truncation happens.
        appendModelAudio(pcm16Bytes)
        // Reuse the same AVAudioFormat instance that engine.connect was called with — see playbackFormat declaration.
        guard let format = playbackFormat else { return }
        let sampleCount = pcm16Bytes.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else { return }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount),
        ) else { return }
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        pcm16Bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let src = raw.bindMemory(to: Int16.self).baseAddress else { return }
            guard let dst = buffer.floatChannelData?[0] else { return }
            for i in 0 ..< sampleCount {
                dst[i] = Float(src[i]) / 32768.0
            }
        }
        playPCM16Count += 1
        let n = playPCM16Count
        if n <= 3 || n % 50 == 0 {
            let p = Self.peakAmplitude(of: buffer)
            logger
                .error(
                    "playPCM16 sched #\(n, privacy: .public): \(pcm16Bytes.count, privacy: .public)B → frames=\(sampleCount, privacy: .public) peak=\(p, privacy: .public) engineRunning=\(self.engine.isRunning, privacy: .public) playerPlaying=\(self.playerNode.isPlaying, privacy: .public)",
                )
        }
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    /// Drop everything queued and resume — caller (AudioPump) hooks this to the realtime client's `bargeIn` stream so
    /// user-speech-detected stops AI audio mid-sentence. `playerNode.stop()` cancels scheduled buffers; immediately
    /// `play()` again so the next AI turn's audio plays without re-entering the start() bring-up.
    func interruptPlayback() {
        playerNode.stop()
        playerNode.play()
    }

    /// Server frames carry Ogg-Opus bytes (encoded by sphn). Demux into raw Opus packets, decode each, schedule for
    /// playback. Loudness handled server-side (see `patch_moshi_server.py`).
    private var playOutputCount = 0

    func playOutput(_ oggBytes: Data) async {
        guard let decoder, let oggReader else { return }
        let packets = oggReader.feed(oggBytes)
        for pkt in packets {
            do {
                let pcm = try decoder.decode(pkt)
                playOutputCount += 1
                if playOutputCount <= 3 || playOutputCount % 100 == 0 {
                    let p = Self.peakAmplitude(of: pcm)
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

    private static func peakAmplitude(of buf: AVAudioPCMBuffer) -> Float {
        guard let ch = buf.floatChannelData else { return 0 }
        let n = Int(buf.frameLength)
        var p: Float = 0
        for i in 0 ..< n {
            let v = abs(ch[0][i])
            if v > p { p = v }
        }
        return p
    }

    private static func copySamples(from buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let count = Int(buffer.frameLength)
        let channels = Int(inputFormat.channelCount)
        var out = [Float](repeating: 0, count: count)
        if channels == 1 {
            let src = UnsafeBufferPointer(start: channelData[0], count: count)
            out = Array(src)
        } else {
            for frame in 0 ..< count {
                var sum: Float = 0
                for channelIndex in 0 ..< channels {
                    sum += channelData[channelIndex][frame]
                }
                out[frame] = sum / Float(channels)
            }
        }
        return out
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
            Self.linearResample(samples, from: inputSampleRate, to: Self.sampleRate)
        }

        pendingMicSamples.append(contentsOf: resampled)

        let frameLen = Int(Self.frameSamples)
        while pendingMicSamples.count >= frameLen {
            var chunk = Array(pendingMicSamples.prefix(frameLen))
            pendingMicSamples.removeFirst(frameLen)

            // Noise gate: zero out frames whose RMS sits at room-tone level. Cuts the chances of OpenAI's server VAD misfiring on wind / scooter rattle / AirPod-bleed of our own TTS. -45 dBFS is conservative — clear speech runs ~ -20 dBFS, room tone ~ -50 to -45. Adjust upward if false positives persist (raise gate), downward if real soft speech is being eaten (lower gate). AEC + voice processing still apply earlier in the chain; this is the final defense.
            if Self.rmsDbfs(chunk) < Self.noiseGateDbfs {
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
            appendSessionAudio(pcm16Bytes)

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
            var oggBytes = oggWriter.headerBytes()
            let wasFirst = !oggBytes.isEmpty
            oggBytes.append(oggWriter.wrap(opusPacket: packet, pcmSampleCount: UInt64(frameLen)))
            if wasFirst {
                logger.info("ogg headers + first audio page emitted, \(oggBytes.count, privacy: .public) bytes")
            }
            inputContinuation?.yield(oggBytes)
        }
    }

    private static func linearResample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let ratio = sourceRate / targetRate
        let outCount = Int(Double(samples.count) / ratio)
        guard outCount > 0 else { return [] }
        var out = [Float](repeating: 0, count: outCount)
        for outIndex in 0 ..< outCount {
            let srcIndex = Double(outIndex) * ratio
            let lowSample = Int(srcIndex)
            let highSample = min(lowSample + 1, samples.count - 1)
            let frac = Float(srcIndex - Double(lowSample))
            out[outIndex] = samples[lowSample] * (1 - frac) + samples[highSample] * frac
        }
        return out
    }
}
