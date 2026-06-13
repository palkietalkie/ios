@preconcurrency import AVFoundation
@testable import PalkieTalkie
import XCTest

final class AudioMathTests: XCTestCase {
    func testRmsDbfsEmptyIsNegativeInfinity() {
        XCTAssertEqual(AudioMath.rmsDbfs([]), -.infinity)
    }

    func testRmsDbfsAllZeroIsNegativeInfinity() {
        XCTAssertEqual(AudioMath.rmsDbfs([0, 0, 0, 0]), -.infinity)
    }

    func testRmsDbfsFullScaleIsZero() {
        // RMS of a constant +1.0 signal is 1.0 → 0 dBFS.
        let v = AudioMath.rmsDbfs([1.0, 1.0, 1.0, 1.0])
        XCTAssertEqual(v, 0.0, accuracy: 0.001)
    }

    func testRmsDbfsHalfScaleIsAbout6dBDown() {
        let v = AudioMath.rmsDbfs([0.5, 0.5, 0.5, 0.5])
        XCTAssertEqual(v, -6.02, accuracy: 0.05)
    }

    func testLinearResampleEmptyIsEmpty() {
        XCTAssertEqual(AudioMath.linearResample([], from: 44100, to: 24000), [])
    }

    func testLinearResampleIdentityRoundsToInputSize() {
        let input: [Float] = (0 ..< 100).map { Float($0) }
        let out = AudioMath.linearResample(input, from: 24000, to: 24000)
        XCTAssertEqual(out.count, 100)
        for (a, b) in zip(out, input) {
            XCTAssertEqual(a, b, accuracy: 0.001)
        }
    }

    func testLinearResampleDownsampleHalvesCount() {
        let input: [Float] = (0 ..< 100).map { _ in 1.0 }
        let out = AudioMath.linearResample(input, from: 48000, to: 24000)
        XCTAssertEqual(out.count, 50)
    }

    func testLinearResampleUpsampleDoublesCount() {
        let input: [Float] = (0 ..< 50).map { _ in 1.0 }
        let out = AudioMath.linearResample(input, from: 24000, to: 48000)
        XCTAssertEqual(out.count, 100)
    }

    func testWavHeaderIsExactly44Bytes() {
        let header = AudioMath.wavHeaderPCM16Mono(sampleRate: 24000, numSamples: 0)
        XCTAssertEqual(header.count, 44)
    }

    func testWavHeaderStartsWithRiffWave() {
        let header = AudioMath.wavHeaderPCM16Mono(sampleRate: 24000, numSamples: 0)
        XCTAssertEqual(String(data: header.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: header.subdata(in: 8 ..< 12), encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: header.subdata(in: 12 ..< 16), encoding: .ascii), "fmt ")
        XCTAssertEqual(String(data: header.subdata(in: 36 ..< 40), encoding: .ascii), "data")
    }

    func testWavHeaderEncodesSampleRateLittleEndian() {
        let header = AudioMath.wavHeaderPCM16Mono(sampleRate: 24000, numSamples: 0)
        // sample rate sits at byte 24, LE u32. 24000 = 0x5DC0 → 0xC0 0x5D 0x00 0x00.
        XCTAssertEqual(header[24], 0xC0)
        XCTAssertEqual(header[25], 0x5D)
        XCTAssertEqual(header[26], 0x00)
        XCTAssertEqual(header[27], 0x00)
    }

    func testCopySamplesMonoPassthrough() throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000,
            channels: 1,
            interleaved: false,
        ),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4)
        else {
            XCTFail("buffer alloc failed")
            return
        }
        buffer.frameLength = 4
        let ch = try XCTUnwrap(buffer.floatChannelData?[0])
        ch[0] = 0.1
        ch[1] = 0.2
        ch[2] = 0.3
        ch[3] = 0.4
        let out = AudioMath.copySamples(from: buffer, inputFormat: format)
        XCTAssertEqual(out, [0.1, 0.2, 0.3, 0.4])
    }

    func testCopySamplesStereoDownmixesToMono() {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000,
            channels: 2,
            interleaved: false,
        ),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3)
        else {
            XCTFail("buffer alloc failed")
            return
        }
        buffer.frameLength = 3
        buffer.floatChannelData?[0][0] = 1.0
        buffer.floatChannelData?[1][0] = 0.0
        buffer.floatChannelData?[0][1] = 0.4
        buffer.floatChannelData?[1][1] = 0.6
        buffer.floatChannelData?[0][2] = -1.0
        buffer.floatChannelData?[1][2] = 1.0
        let out = AudioMath.copySamples(from: buffer, inputFormat: format)
        XCTAssertEqual(out[0], 0.5, accuracy: 0.001)
        XCTAssertEqual(out[1], 0.5, accuracy: 0.001)
        XCTAssertEqual(out[2], 0.0, accuracy: 0.001)
    }

    func testPeakAmplitudeOfBufferReturnsAbsoluteMax() throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000,
            channels: 1,
            interleaved: false,
        ),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4)
        else {
            XCTFail("buffer alloc failed")
            return
        }
        buffer.frameLength = 4
        let ch = try XCTUnwrap(buffer.floatChannelData?[0])
        ch[0] = 0.1
        ch[1] = -0.9
        ch[2] = 0.5
        ch[3] = 0.0
        XCTAssertEqual(AudioMath.peakAmplitude(of: buffer), 0.9, accuracy: 0.001)
    }

    func testDataInitLittleEndianRoundTrip() {
        let original: UInt32 = 0xDEAD_BEEF
        let data = Data(littleEndian: original)
        XCTAssertEqual(data.count, 4)
        // LE: low byte first.
        XCTAssertEqual(data[0], 0xEF)
        XCTAssertEqual(data[1], 0xBE)
        XCTAssertEqual(data[2], 0xAD)
        XCTAssertEqual(data[3], 0xDE)
    }

    func testDataAppendLittleEndianAppendsLowByteFirst() {
        var data = Data()
        data.append(littleEndian: UInt16(0x1234))
        XCTAssertEqual(data, Data([0x34, 0x12]))
    }

    // MARK: - Saturated-burst hearing-safety guard

    func testCleanSpeechIsNotASaturatedBurst() {
        // A 24kHz sine at -6 dBFS — loud, normal speech-band audio. Zero samples at the rail.
        let samples: [Float] = (0 ..< 480).map { 0.5 * sin(2 * .pi * 200 * Float($0) / 24000) }
        XCTAssertEqual(AudioMath.railFraction(samples), 0, accuracy: 0.0001)
        XCTAssertFalse(AudioMath.isSaturatedBurst(samples))
    }

    func testFullScaleStaticBurstIsDetected() {
        // The measured fingerprint: ~99% of samples pinned to ±full-scale (a square-wave white-noise burst).
        let samples: [Float] = (0 ..< 480).map { $0 % 2 == 0 ? 1.0 : -1.0 }
        XCTAssertEqual(AudioMath.railFraction(samples), 1.0, accuracy: 0.0001)
        XCTAssertTrue(AudioMath.isSaturatedBurst(samples))
    }

    func testQuarterRailedChunkIsDropped() {
        // 25% at the rail exceeds the 20% gate → dropped. (Real speech never reaches this.)
        var samples = [Float](repeating: 0.1, count: 480)
        for i in 0 ..< 120 {
            samples[i] = 1.0
        }
        XCTAssertTrue(AudioMath.isSaturatedBurst(samples))
    }

    func testTenPercentRailedChunkIsKept() {
        // 10% at the rail is below the gate → kept; protects against false-dropping a genuinely loud transient.
        var samples = [Float](repeating: 0.1, count: 480)
        for i in 0 ..< 48 {
            samples[i] = 1.0
        }
        XCTAssertFalse(AudioMath.isSaturatedBurst(samples))
    }

    func testEmptyChunkIsNotASaturatedBurst() {
        XCTAssertFalse(AudioMath.isSaturatedBurst([]))
    }

    // MARK: - PCM16 chunk framing (odd-byte carry)

    func testFramePCM16EvenChunkDecodesAllSamples() {
        // Two little-endian Int16 samples: 0x0100 = 256, 0x7FFF = 32767.
        let (samples, carry) = AudioMath.framePCM16(carry: Data(), appending: Data([0x00, 0x01, 0xFF, 0x7F]))
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0], 256.0 / 32768.0, accuracy: 1e-6)
        XCTAssertEqual(samples[1], 32767.0 / 32768.0, accuracy: 1e-6)
        XCTAssertTrue(carry.isEmpty)
    }

    func testFramePCM16OddChunkCarriesTrailingByte() {
        // 3 bytes = one whole sample (0x4000 = 16384) + one leftover byte that MUST be carried, not dropped.
        let (samples, carry) = AudioMath.framePCM16(carry: Data(), appending: Data([0x00, 0x40, 0x00]))
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0], 16384.0 / 32768.0, accuracy: 1e-6)
        XCTAssertEqual(carry, Data([0x00]))
    }

    func testFramePCM16SampleStraddlingOddBoundaryReconstructsIdentically() {
        // The bug this fixes: the same byte stream split on an odd boundary must yield identical samples.
        let stream = Data([0x11, 0x22, 0x33, 0x44]) // samples 0x2211, 0x4433
        let (reference, _) = AudioMath.framePCM16(carry: Data(), appending: stream)
        // Split after 1 byte (odd) across two chunks — the old per-chunk `count / 2` would corrupt this.
        let (first, carry1) = AudioMath.framePCM16(carry: Data(), appending: Data([0x11]))
        let (second, carry2) = AudioMath.framePCM16(carry: carry1, appending: Data([0x22, 0x33, 0x44]))
        XCTAssertTrue(first.isEmpty) // one byte → no whole sample yet
        XCTAssertEqual(second.count, 2)
        XCTAssertTrue(carry2.isEmpty)
        XCTAssertEqual(second[0], reference[0], accuracy: 1e-6)
        XCTAssertEqual(second[1], reference[1], accuracy: 1e-6)
    }

    func testFramePCM16EmptyChunkWithCarryHoldsByte() {
        let (samples, carry) = AudioMath.framePCM16(carry: Data([0xAB]), appending: Data())
        XCTAssertTrue(samples.isEmpty)
        XCTAssertEqual(carry, Data([0xAB]))
    }

    func testSaturatedBurstBufferOverloadMatches() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000,
            channels: 1,
            interleaved: false,
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
        buffer.frameLength = 480
        let ch = try XCTUnwrap(buffer.floatChannelData?[0])
        for i in 0 ..< 480 {
            ch[i] = i % 2 == 0 ? 1.0 : -1.0
        }
        XCTAssertTrue(AudioMath.isSaturatedBurst(buffer))
    }
}
