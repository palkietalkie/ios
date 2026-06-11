import Foundation

/// Demuxes an Ogg-Opus byte stream into raw Opus packets, the inverse of `OggOpusWriter`.
///
/// Why this exists: NVIDIA's PersonaPlex server (`sphn.OpusStreamWriter`) emits Ogg-encapsulated Opus over the WebSocket. Swift's `Opus.Decoder.decode(_:)` expects RAW Opus packets, not Ogg pages. Feeding Ogg page bytes directly into the raw decoder fails silently (we `try?`), and the user hears nothing while the model is happily generating audio server-side.
///
/// Bytes can arrive in arbitrarily-sized WS messages; an Ogg page can be split across messages and multiple pages can land in a single message. The reader buffers partial input and emits whole packets as they become complete.
///
/// Header pages (OpusHead, OpusTags) are recognized and skipped — those carry metadata for an Ogg-aware decoder, not audio to play.
final class OggOpusReader {
    private var buffer = Data()

    /// Feed bytes from the WebSocket. Returns zero or more complete Opus packets ready to play.
    func feed(_ bytes: Data) -> [Data] {
        buffer.append(bytes)
        var packets: [Data] = []
        while let page = nextPage() {
            packets.append(contentsOf: page.opusPackets)
        }
        return packets
    }

    /// Try to parse one full Ogg page from the head of `buffer`. Returns nil if there's not enough bytes yet for a complete page. On success, consumes the page from `buffer`.
    private func nextPage() -> OggPage? {
        // Minimum Ogg page is 27 bytes (header) + 1 (num_segments) = 28 bytes; segment table follows.
        let headerSize = 27
        guard buffer.count >= headerSize + 1 else { return nil }

        // Find "OggS" magic. Buffer may have stray bytes (shouldn't on a clean WS stream, but be defensive).
        guard let magicIdx = findOggSMagicIndex(in: buffer) else {
            // No magic in buffer; drop everything (it can't form a page). Keep last 3 bytes in case "Ogg" prefix is split across reads.
            if buffer.count > 3 { buffer.removeFirst(buffer.count - 3) }
            return nil
        }
        if magicIdx > 0 {
            buffer.removeFirst(magicIdx)
        }
        guard buffer.count >= headerSize + 1 else { return nil }

        let numSegments = Int(buffer[buffer.startIndex + 26])
        let segTableStart = buffer.startIndex + 27
        guard buffer.count >= 27 + numSegments else { return nil }

        // Segment table tells us packet length. Sum up byte counts.
        var pageDataLen = 0
        var packetSizes: [Int] = []
        var current = 0
        for i in 0 ..< numSegments {
            let seg = Int(buffer[segTableStart + i])
            pageDataLen += seg
            current += seg
            // A segment of <255 marks end of an Opus packet. Exactly 255 means "continues into next segment".
            if seg < 255 {
                packetSizes.append(current)
                current = 0
            }
        }
        // If the page ends mid-packet (last segment was 255), the partial trailing bytes belong to a packet that continues on the next page. We add a "partial" entry; the next page will start with the continuation. For simplicity we treat full-page-ends-mid-packet as the packet ending here too — fine for streaming silence/voice frames which are well under 255 bytes each.
        if current > 0 {
            packetSizes.append(current)
        }

        let payloadStart = segTableStart + numSegments
        guard buffer.count >= 27 + numSegments + pageDataLen else { return nil }

        // Slice out the packets.
        var packets: [Data] = []
        var offset = payloadStart
        for size in packetSizes {
            let pkt = Data(buffer[offset ..< offset + size])
            offset += size
            packets.append(pkt)
        }

        let headerType = buffer[buffer.startIndex + 5]
        let isBOS = (headerType & 0x02) != 0
        // Skip header packets (OpusHead, OpusTags). Detect by content: OpusHead starts with "OpusHead", OpusTags with "OpusTags". The BOS flag marks the first page but a BOS page can also carry audio in some Ogg variants; check magic explicitly.
        let opusPackets = packets.filter { pkt in
            !isHeaderPacket(pkt) && !pkt.isEmpty
        }
        _ = isBOS

        buffer.removeFirst(27 + numSegments + pageDataLen)
        return OggPage(opusPackets: opusPackets)
    }

    private func isHeaderPacket(_ pkt: Data) -> Bool {
        guard pkt.count >= 8 else { return false }
        let head = pkt.prefix(8)
        return head == Data("OpusHead".utf8) || head == Data("OpusTags".utf8)
    }

    private func findOggSMagicIndex(in data: Data) -> Int? {
        let magic: [UInt8] = [0x4F, 0x67, 0x67, 0x53]
        let count = data.count
        guard count >= 4 else { return nil }
        var i = 0
        while i <= count - 4 {
            if data[data.startIndex + i] == magic[0],
               data[data.startIndex + i + 1] == magic[1],
               data[data.startIndex + i + 2] == magic[2],
               data[data.startIndex + i + 3] == magic[3]
            {
                return i
            }
            i += 1
        }
        return nil
    }

    private struct OggPage {
        let opusPackets: [Data]
    }
}
