@testable import PalkieTalkie
import XCTest

/// Regression test for the audio-doesn't-play bug. Server emits Ogg-Opus pages; if iOS forgets to demux them before
/// feeding swift-opus's raw decoder, decoding silently fails and the user hears nothing while the model is generating
/// audio fine server-side.
///
/// The contract here: feed the reader the byte stream that an `OggOpusWriter` (the upstream side) produced, get back
/// the exact same Opus packets that went in, in order, with no header packets leaked through.
@MainActor
final class OggOpusReaderTests: XCTestCase {
    func test_reader_round_trips_packets_through_writer() {
        let writer = OggOpusWriter(sampleRate: 24000, channels: 1)
        let pkts: [Data] = [
            Data([0x10, 0xAA, 0xBB]),
            Data([0x20, 0xCC, 0xDD, 0xEE]),
            Data([0x30, 0x01, 0x02, 0x03, 0x04, 0x05])
        ]

        var stream = writer.headerBytes()
        for p in pkts {
            stream.append(writer.wrap(opusPacket: p, pcmSampleCount: 480))
        }

        let reader = OggOpusReader()
        let out = reader.feed(stream)

        XCTAssertEqual(out, pkts, "reader should yield the original Opus packets, headers filtered out")
    }

    func test_reader_handles_chunked_input() {
        // Ogg pages can split across multiple WS messages; the reader has to buffer until a full page is available.
        let writer = OggOpusWriter(sampleRate: 24000, channels: 1)
        let pkt = Data((0 ..< 50).map { UInt8($0 & 0xFF) })

        var stream = writer.headerBytes()
        stream.append(writer.wrap(opusPacket: pkt, pcmSampleCount: 480))

        let reader = OggOpusReader()
        // Feed one byte at a time. Most calls yield nothing; the last byte of the final page yields the packet.
        var collected: [Data] = []
        for i in 0 ..< stream.count {
            let chunk = stream.subdata(in: i ..< (i + 1))
            collected.append(contentsOf: reader.feed(chunk))
        }
        XCTAssertEqual(collected, [pkt], "byte-by-byte feed should still produce the same packet")
    }

    func test_reader_skips_header_packets() {
        // headerBytes() emits OpusHead + OpusTags packets. Those are metadata; they must NOT reach the audio decoder.
        let writer = OggOpusWriter(sampleRate: 24000, channels: 1)
        let reader = OggOpusReader()
        let out = reader.feed(writer.headerBytes())
        XCTAssertEqual(out, [], "header-only stream should yield zero playable packets")
    }
}
