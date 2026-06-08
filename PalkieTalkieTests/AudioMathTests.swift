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
}
