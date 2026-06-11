@testable import PalkieTalkie
import XCTest

/// Direct tests for OggOpusWriter — wraps raw Opus packets in Ogg pages per RFC 3533/7845. Existing `OggOpusReaderTests` round-trips through the writer; this file pins specific bytes the wire format requires (RIFF-like header signature, CRC computation, segment table encoding for 255-byte boundary cases).
final class OggOpusWriterTests: XCTestCase {
    func testHeaderBytesEmitsTwoOggPagesOnce() {
        let writer = OggOpusWriter()
        let first = writer.buildHeaderBytes()
        XCTAssertFalse(first.isEmpty, "first call should emit OpusHead + OpusTags pages")
        // Each page starts with "OggS" magic.
        XCTAssertEqual(first[0 ..< 4], Data([0x4F, 0x67, 0x67, 0x53]))

        // Calling twice should return empty — headers are emit-once.
        let second = writer.buildHeaderBytes()
        XCTAssertTrue(second.isEmpty)
    }

    func testWrapEmitsOggPageWithCorrectMagic() {
        let writer = OggOpusWriter()
        _ = writer.buildHeaderBytes()
        let opusFrame = Data([0xA0, 0xB1, 0xC2, 0xD3])
        let page = writer.wrap(opusPacket: opusFrame, pcmSampleCount: 480)
        XCTAssertEqual(page[0 ..< 4], Data([0x4F, 0x67, 0x67, 0x53]), "wrapped page must start with OggS")
    }

    func testGranulePositionAccumulates() {
        let writer = OggOpusWriter()
        _ = writer.buildHeaderBytes()
        let frame = Data(repeating: 0x55, count: 10)
        let p1 = writer.wrap(opusPacket: frame, pcmSampleCount: 480)
        let p2 = writer.wrap(opusPacket: frame, pcmSampleCount: 480)
        // Granule is at bytes 6..14 of the Ogg page header, little-endian UInt64. Page 1 = 480, page 2 = 960.
        let g1 = p1.subdata(in: 6 ..< 14).withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
        let g2 = p2.subdata(in: 6 ..< 14).withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
        XCTAssertEqual(g1, 480)
        XCTAssertEqual(g2, 960)
    }

    /// A packet whose length is an exact multiple of 255 must encode a trailing zero-length segment entry per RFC 3533. Locks in the boundary handling that's easy to miss in a refactor.
    func testWrapHandlesPacketExactly255BytesWithTrailingZeroSegment() {
        let writer = OggOpusWriter()
        _ = writer.buildHeaderBytes()
        let packet = Data(repeating: 0xAA, count: 255)
        let page = writer.wrap(opusPacket: packet, pcmSampleCount: 480)
        // Segment table starts at byte 27 (4 magic + 1 ver + 1 flags + 8 granule + 4 serial + 4 seq + 4 crc + 1 segCount). Number of segments at offset 26.
        let segCount = Int(page[26])
        XCTAssertEqual(segCount, 2, "255-byte packet requires segment-of-255 + terminating-segment-of-0")
        XCTAssertEqual(page[27], 255)
        XCTAssertEqual(page[28], 0)
    }

    /// Packets >255 bytes split across multiple 255-byte segments. A 600-byte packet → segments [255, 255, 90].
    func testWrapSplitsLargePacketIntoSegments() {
        let writer = OggOpusWriter()
        _ = writer.buildHeaderBytes()
        let packet = Data(repeating: 0x77, count: 600)
        let page = writer.wrap(opusPacket: packet, pcmSampleCount: 480)
        let segCount = Int(page[26])
        XCTAssertEqual(segCount, 3)
        XCTAssertEqual(page[27], 255)
        XCTAssertEqual(page[28], 255)
        XCTAssertEqual(page[29], 90)
    }

    /// The CRC field at bytes 22..26 should be a valid Ogg-CRC32 computed over the entire page with the CRC field zeroed. Reusing the writer's own CRC computation by reconstructing the page should match.
    func testWrapCRC32IsValid() {
        let writer = OggOpusWriter()
        _ = writer.buildHeaderBytes()
        let packet = Data(repeating: 0x42, count: 16)
        let page = writer.wrap(opusPacket: packet, pcmSampleCount: 480)
        // Re-compute by zeroing the CRC field and running the writer's crc.
        var zeroed = page
        zeroed.replaceSubrange(22 ..< 26, with: Data([0, 0, 0, 0]))
        let expected = oggCRC32(zeroed)
        let actual = page.subdata(in: 22 ..< 26).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        XCTAssertEqual(expected, actual)
    }

    /// OggOpusReader should round-trip whatever OggOpusWriter emits. Same as OggOpusReaderTests but minimal end-to-end here so this file's tests catch a writer-only regression.
    func testWriterReaderRoundTripPreservesOpusBytes() {
        let writer = OggOpusWriter()
        let reader = OggOpusReader()
        var stream = writer.buildHeaderBytes()
        let originalOpus = Data((0 ..< 32).map { UInt8($0) })
        stream.append(writer.wrap(opusPacket: originalOpus, pcmSampleCount: 480))
        let recovered = reader.feed(stream)
        XCTAssertEqual(recovered.first, originalOpus)
    }
}
