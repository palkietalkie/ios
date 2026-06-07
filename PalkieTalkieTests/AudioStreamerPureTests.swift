@testable import PalkieTalkie
import XCTest

/// Pure-function coverage for AudioStreamer's static helpers — no AVAudioEngine, no actor bring-up.
final class AudioStreamerPureTests: XCTestCase {
    // MARK: - rmsDbfs

    func testRmsDbfsReturnsInfinityForEmpty() {
        XCTAssertEqual(AudioStreamer.rmsDbfs([]), -.infinity)
    }

    func testRmsDbfsReturnsInfinityForAllZeros() {
        XCTAssertEqual(AudioStreamer.rmsDbfs([0, 0, 0, 0]), -.infinity)
    }

    func testRmsDbfsFullScale() {
        // RMS of constant ±1 samples = 1.0, which is 20*log10(1) = 0 dBFS.
        let samples: [Float] = [1, -1, 1, -1, 1, -1]
        XCTAssertEqual(AudioStreamer.rmsDbfs(samples), 0, accuracy: 0.01)
    }

    func testRmsDbfsHalfScale() {
        // RMS of constant ±0.5 = 0.5 → 20*log10(0.5) ≈ -6.02 dBFS.
        let samples: [Float] = [0.5, -0.5, 0.5, -0.5]
        XCTAssertEqual(AudioStreamer.rmsDbfs(samples), -6.02, accuracy: 0.05)
    }

    func testNoiseGateBelowCutoff() {
        // -45 dBFS gate. A tiny constant amplitude (e.g. 0.001) → 20*log10(0.001) = -60 dBFS, below the gate.
        let tiny = [Float](repeating: 0.001, count: 480)
        XCTAssertLessThan(AudioStreamer.rmsDbfs(tiny), AudioStreamer.noiseGateDbfs)
    }

    // MARK: - WAV header

    func testWavHeaderBasicFields() {
        let header = AudioStreamer.wavHeaderPCM16Mono(sampleRate: 24000, numSamples: 0)
        XCTAssertEqual(header.count, 44, "RIFF + WAVE + fmt + data header is exactly 44 bytes")
        XCTAssertEqual(String(data: header[0 ..< 4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: header[8 ..< 12], encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: header[12 ..< 16], encoding: .ascii), "fmt ")
        XCTAssertEqual(String(data: header[36 ..< 40], encoding: .ascii), "data")
    }

    func testWavHeaderSampleRateIsLittleEndian() {
        let header = AudioStreamer.wavHeaderPCM16Mono(sampleRate: 24000, numSamples: 0)
        // Sample rate is at offset 24 (RFC: 4 + 4 + 4 + 4 + 2 + 2 = 20 from end of "WAVE", or absolute 24).
        let bytes = Array(header[24 ..< 28])
        // 24000 = 0x00005DC0 → LE = C0 5D 00 00
        XCTAssertEqual(bytes, [0xC0, 0x5D, 0x00, 0x00])
    }

    func testWavHeaderEncodesPCMFormatTag() {
        let header = AudioStreamer.wavHeaderPCM16Mono(sampleRate: 24000, numSamples: 0)
        // Audio format = 1 (PCM), 1 channel.
        XCTAssertEqual(Array(header[20 ..< 22]), [0x01, 0x00])
        XCTAssertEqual(Array(header[22 ..< 24]), [0x01, 0x00])
    }

    func testWavHeaderDataSizeReflectsSampleCount() {
        // 480 samples × 2 bytes/sample (16-bit mono) = 960 bytes of audio data.
        let header = AudioStreamer.wavHeaderPCM16Mono(sampleRate: 24000, numSamples: 480)
        let dataBytes = Array(header[40 ..< 44])
        XCTAssertEqual(dataBytes, [0xC0, 0x03, 0x00, 0x00], "960 LE = C0 03 00 00")
    }

    // MARK: - Data little-endian extension

    func testDataLittleEndianInitAppend() {
        var data = Data(littleEndian: UInt32(1))
        XCTAssertEqual(Array(data), [0x01, 0x00, 0x00, 0x00])
        data.append(littleEndian: UInt16(0xABCD))
        XCTAssertEqual(Array(data.suffix(2)), [0xCD, 0xAB])
    }
}
