@preconcurrency import AVFoundation
import Opus
@testable import PalkieTalkie
import XCTest

/// We don't boot AVAudioEngine in tests (the simulator has no mic and CI doesn't either). Instead we verify the Opus
/// codec contract the streamer depends on: 24kHz mono, 480-sample frames (20ms VoIP), encode→decode round-trip produces
/// a buffer of the expected size.
final class AudioStreamerTests: XCTestCase {
    private var opusFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioStreamer.sampleRate,
            channels: 1,
            interleaved: false,
        )!
    }

    func testFrameSizeIs480SamplesAt24kHz() {
        // 480 samples / 24000 Hz = 20ms — the VoIP frame size PersonaPlex expects.
        XCTAssertEqual(AudioStreamer.sampleRate, 24000)
        XCTAssertEqual(AudioStreamer.frameSamples, 480)
    }

    func testOpusEncodeDecodeRoundTrip() throws {
        let encoder = try Opus.Encoder(format: opusFormat, application: .voip)
        let decoder = try Opus.Decoder(format: opusFormat)

        let frameLen = Int(AudioStreamer.frameSamples)
        guard let buf = AVAudioPCMBuffer(
            pcmFormat: opusFormat,
            frameCapacity: AVAudioFrameCount(frameLen),
        ) else {
            return XCTFail("could not allocate PCM buffer")
        }
        buf.frameLength = AVAudioFrameCount(frameLen)
        // 440Hz tone — non-silence so the encoder produces something interesting.
        let samples = (0 ..< frameLen).map { sampleIndex -> Float in
            Float(sin(2.0 * .pi * 440.0 * Double(sampleIndex) / AudioStreamer.sampleRate)) * 0.5
        }
        samples.withUnsafeBufferPointer { src in
            buf.floatChannelData![0].update(from: src.baseAddress!, count: frameLen)
        }

        var packet = Data(count: 1500)
        let encoded = try encoder.encode(buf, to: &packet)
        XCTAssertGreaterThan(encoded, 0)
        packet.removeSubrange(encoded ..< packet.count)

        let decoded = try decoder.decode(packet)
        // Opus restores the same frame size — 20ms at 24kHz = 480 samples.
        XCTAssertEqual(Int(decoded.frameLength), frameLen)
        XCTAssertEqual(decoded.format.sampleRate, AudioStreamer.sampleRate)
        XCTAssertEqual(decoded.format.channelCount, 1)
    }
}
