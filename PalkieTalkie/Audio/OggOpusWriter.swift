import Foundation

/// Wraps raw Opus packets in Ogg (the Xiph.Org container format — "Ogg" is just the name, not an abbreviation) pages per RFC 3533 + RFC 7845.
///
/// Why this exists: `swift-opus` emits raw Opus packets with no framing. NVIDIA's PersonaPlex server uses `sphn.OpusStreamReader` which expects Ogg-Opus stream bytes. Without framing, the server can't tell where one packet ends and the next begins, silently fails to decode, and the model never advances.
///
/// Output bytes from this writer are appended to a WebSocket binary message (prefixed with our `0x01` audio frame tag).
/// The first call returns the two Ogg header pages (OpusHead + OpusTags); subsequent calls return audio data pages.
///
/// Implementation notes:
/// - One Opus packet per Ogg page (simplest valid layout). Real opus-recorder batches packets, but per-page packing is correct and trivially decoded.
/// - Granule position = cumulative PCM (Pulse Code Modulation — raw audio samples) sample count. Each 20ms frame at 24kHz = 480 samples.
/// - Pre-skip = 0 (no codec-warmup samples to discard for our streaming use).
/// - Channel mapping family = 0 (mono / stereo simple layout).
/// - CRC32 (Cyclic Redundancy Check, 32-bit) uses Ogg's polynomial 0x04c11db7 per RFC 3533.
final class OggOpusWriter {
    private let sampleRate: UInt32
    private let channels: UInt8
    private let serialNumber: UInt32
    private var pageSequence: UInt32 = 0
    private var granulePosition: UInt64 = 0
    private var headersEmitted = false

    init(sampleRate: UInt32 = 24000, channels: UInt8 = 1) {
        self.sampleRate = sampleRate
        self.channels = channels
        // Random per-stream so concurrent streams from one client never collide if multiplexed.
        serialNumber = UInt32.random(in: 1 ..< UInt32.max)
    }

    /// Returns the bytes to prepend on the first audio call (OpusHead + OpusTags pages). Internally tracks emission so calling twice is safe (returns empty Data the second time).
    func buildHeaderBytes() -> Data {
        guard !headersEmitted else { return Data() }
        headersEmitted = true
        var out = Data()
        out.append(makePage(packet: opusHeadPacket(), headerType: .bos, granule: 0))
        out.append(makePage(packet: opusTagsPacket(), headerType: .none, granule: 0))
        return out
    }

    /// Wrap one Opus packet (covering `pcmSampleCount` samples — e.g. 480 for a 20ms frame at 24kHz) in a single Ogg page. Caller is responsible for not calling this before `buildHeaderBytes()`.
    func wrap(opusPacket: Data, pcmSampleCount: UInt64) -> Data {
        granulePosition &+= pcmSampleCount
        return makePage(packet: opusPacket, headerType: .none, granule: granulePosition)
    }

    // MARK: - Internals

    private enum HeaderType: UInt8 {
        case none = 0x00
        case continued = 0x01
        case bos = 0x02 // Beginning Of Stream
        case eos = 0x04 // End Of Stream
    }

    /// Build a single Ogg page containing exactly one Opus packet. RFC 3533 §6.
    private func makePage(packet: Data, headerType: HeaderType, granule: UInt64) -> Data {
        // Segment table: split the packet into 255-byte segments. A segment of length < 255 marks the end of the packet. An empty packet is encoded as one segment of length 0.
        var segmentTable: [UInt8] = []
        var remaining = packet.count
        if remaining == 0 {
            segmentTable.append(0)
        } else {
            while remaining > 0 {
                let take = min(remaining, 255)
                segmentTable.append(UInt8(take))
                remaining -= take
                if take < 255 { break }
            }
            // If the packet length is an exact multiple of 255, append a 0-length lacing value to signal "packet ends here, not continued into next page."
            if packet.count % 255 == 0 {
                segmentTable.append(0)
            }
        }

        // 27-byte fixed header + segment table + payload
        var page = Data()
        page.append(contentsOf: [0x4F, 0x67, 0x67, 0x53]) // "OggS"
        page.append(0x00) // stream structure version
        page.append(headerType.rawValue)
        page.appendLittleEndian(UInt64(bitPattern: Int64(granule)))
        page.appendLittleEndian(serialNumber)
        page.appendLittleEndian(pageSequence)
        page.appendLittleEndian(UInt32(0)) // checksum placeholder, filled below
        page.append(UInt8(segmentTable.count))
        page.append(contentsOf: segmentTable)
        page.append(packet)

        // Compute CRC over the whole page (with checksum field zeroed in place — it already is) and patch it in at offset 22.
        let crc = oggCRC32(page)
        page.replaceSubrange(22 ..< 26, with: crc.littleEndianBytes)

        pageSequence &+= 1
        return page
    }

    private func opusHeadPacket() -> Data {
        // RFC 7845 §5.1
        var p = Data()
        p.append(contentsOf: Array("OpusHead".utf8))
        p.append(0x01) // version
        p.append(channels)
        p.appendLittleEndian(UInt16(0)) // pre-skip = 0
        p.appendLittleEndian(sampleRate)
        p.appendLittleEndian(UInt16(0)) // output gain (Q7.8) = 0
        p.append(0x00) // channel mapping family (0 = mono/stereo simple)
        return p
    }

    private func opusTagsPacket() -> Data {
        // RFC 7845 §5.2 — minimal: vendor string, zero user comments.
        let vendor = "PalkieTalkie"
        var p = Data()
        p.append(contentsOf: Array("OpusTags".utf8))
        p.appendLittleEndian(UInt32(vendor.utf8.count))
        p.append(contentsOf: Array(vendor.utf8))
        p.appendLittleEndian(UInt32(0)) // user comment count
        return p
    }
}

// MARK: - CRC32 with Ogg's polynomial (RFC 3533 §6)

private let oggCRCTable: [UInt32] = {
    var table = [UInt32](repeating: 0, count: 256)
    let poly: UInt32 = 0x04C1_1DB7
    for i in 0 ..< 256 {
        var r = UInt32(i) << 24
        for _ in 0 ..< 8 {
            r = (r & 0x8000_0000) != 0 ? (r << 1) ^ poly : (r << 1)
        }
        table[i] = r & 0xFFFF_FFFF
    }
    return table
}()

func oggCRC32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0
    for byte in data {
        let idx = Int((crc >> 24) ^ UInt32(byte)) & 0xFF
        crc = (crc << 8) ^ oggCRCTable[idx]
    }
    return crc
}

// MARK: - Little-endian append helpers

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        append(contentsOf: (0 ..< 4).map { UInt8((value >> ($0 * 8)) & 0xFF) })
    }

    mutating func appendLittleEndian(_ value: UInt64) {
        append(contentsOf: (0 ..< 8).map { UInt8((value >> ($0 * 8)) & 0xFF) })
    }
}

private extension UInt32 {
    var littleEndianBytes: [UInt8] {
        (0 ..< 4).map { UInt8((self >> ($0 * 8)) & 0xFF) }
    }
}
