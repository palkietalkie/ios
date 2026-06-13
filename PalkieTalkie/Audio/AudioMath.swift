@preconcurrency import AVFoundation
import Foundation

/// Pure audio-math statics — RMS dBFS, peak amplitude, mono/multi-channel sample copy, linear resampling, WAV-RIFF header bytes. Lives outside `AudioStreamer` so the engine actor stays focused on the audio-graph state machine and these helpers stay testable without AVAudioEngine.
enum AudioMath {
    /// Root-Mean-Square of a Float32 frame, returned in dBFS (decibels relative to full scale). Returns -∞ for true silence. Used by AudioStreamer's noise gate; not for any decoder math.
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

    /// Peak absolute amplitude across the buffer's first channel. Used for diagnostic logging.
    static func peakAmplitude(of buf: AVAudioPCMBuffer) -> Float {
        guard let ch = buf.floatChannelData else { return 0 }
        let n = Int(buf.frameLength)
        var p: Float = 0
        for i in 0 ..< n {
            let v = abs(ch[0][i])
            if v > p { p = v }
        }
        return p
    }

    /// A sample's |amplitude| on a 0.0…1.0 scale (0 = silence, 1.0 = full scale = the rail). At/above this counts as railed; 0.9 (not 1.0) catches samples just below the hard limit. See JARGON: rail.
    static let railLevel: Float = 0.9
    /// Drop a chunk when this fraction of THE CHUNK'S samples are railed — 0.0 = none, 1.0 = every sample in the chunk. 0.2 = 20%. Real speech rails ~0% even when loud; corrupt static bursts rail 60–99%, so 0.2 sits far above real audio and far below a burst.
    static let saturationDropFraction: Float = 0.2

    /// Frame a streaming chunk of little-endian PCM16 into normalized Float samples, carrying any trailing odd byte to the next call. PCM16 is 2 bytes/sample and a network chunk can split a sample across its boundary; dropping the leftover byte (instead of carrying it) byte-shifts every following sample into full-scale static until the stream self-realigns. Returns the decoded samples plus the 0-or-1 carry byte to pass back on the next call. Bytes are read pairwise (not via `bindMemory(to: Int16.self)`) so we don't rely on the buffer being 2-byte aligned.
    static func framePCM16(carry: Data, appending chunk: Data) -> (samples: [Float], carry: Data) {
        var bytes = carry
        bytes.append(chunk)
        let sampleCount = bytes.count / 2
        let nextCarry = bytes.count % 2 == 1 ? Data(bytes.suffix(1)) : Data()
        guard sampleCount > 0 else { return ([], nextCarry) }
        var out = [Float](repeating: 0, count: sampleCount)
        bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0 ..< sampleCount {
                let lo = UInt16(raw[2 * i]) // low byte first (little-endian)
                let hi = UInt16(raw[2 * i + 1])
                // 32768 = 2^15 = one past the max magnitude of a signed 16-bit int, so dividing maps the Int16 range (-32768…32767) onto normalized float [-1, 1).
                out[i] = Float(Int16(bitPattern: lo | (hi << 8))) / 32768.0
            }
        }
        return (out, nextCarry)
    }

    /// Fraction of samples whose magnitude is at the full-scale rail.
    static func railFraction(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var railed = 0
        for s in samples where abs(s) >= railLevel {
            railed += 1
        }
        return Float(railed) / Float(samples.count)
    }

    /// True when a chunk is a pathological full-scale burst — the fingerprint of corrupt or clipped audio (e.g. a realtime-model glitch) that plays as ear-damaging full-scale static. The caller MUST drop such a chunk: a brief silence is safe, a 0 dBFS noise blast into earbuds is not.
    static func isSaturatedBurst(_ samples: [Float]) -> Bool {
        railFraction(samples) >= saturationDropFraction
    }

    /// Buffer overload — same rule applied to a decoded `AVAudioPCMBuffer` (PersonaPlex/Opus path) without copying it to an array.
    static func isSaturatedBurst(_ buf: AVAudioPCMBuffer) -> Bool {
        guard let ch = buf.floatChannelData else { return false }
        let n = Int(buf.frameLength)
        guard n > 0 else { return false }
        var railed = 0
        for i in 0 ..< n where abs(ch[0][i]) >= railLevel {
            railed += 1
        }
        return Float(railed) >= Float(n) * saturationDropFraction
    }

    /// Downmix-to-mono copy. Mono input passes through; multi-channel averages across channels per-frame so we hand the encoder one channel at the right sample count.
    static func copySamples(from buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) -> [Float] {
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

    /// Linear-interpolation resample. Cheaper than AVAudioConverter and good enough for voice — the encoder catches any spectral aliasing.
    static func linearResample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
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

    /// 44-byte WAV (RIFF) header for PCM16 mono at the given sample rate. The two size fields (RIFF chunk + data chunk) are placeholders; the caller patches them at close-time when the real sample count is known. Layout per http://soundfile.sapp.org/doc/WaveFormat/.
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
}

/// Tiny helpers for building the WAV header (little-endian by spec, regardless of host endianness). Inlined here because AudioMath is the only consumer.
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
