@preconcurrency import AVFoundation
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.palkietalkie", category: "audio.recorder")

/// Best-effort wav recorder over a single FileHandle. Used twice by AudioStreamer: once for the user-side mic-stream wav (`session-<uuid>.wav`) and once for the model-side raw output wav (`model-<uuid>.wav`). Both need the same open / append / close-with-header-fixup dance — extracting it removed ~60 lines of straight duplication.
///
/// Errors are logged but never thrown. Recording is best-effort; a write failure must not block the real-time audio path.
final class WavAudioRecorder {
    private let prefix: String
    private let sampleRate: UInt32
    private var handle: FileHandle?
    private(set) var url: URL?
    private(set) var samplesWritten: UInt32 = 0

    /// `prefix` ends up in the temp filename — e.g. "session" → `/tmp/session-<uuid>.wav`. Used to tell session vs model files apart on disk.
    init(prefix: String, sampleRate: UInt32) {
        self.prefix = prefix
        self.sampleRate = sampleRate
    }

    /// Open a fresh wav in the system temp dir and write a placeholder 44-byte header. Idempotent in the sense that a prior call's state is overwritten.
    func open() {
        samplesWritten = 0
        let id = UUID().uuidString
        let newURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(prefix)-\(id).wav",
        )
        url = newURL
        FileManager.default.createFile(atPath: newURL.path, contents: nil)
        do {
            let h = try FileHandle(forWritingTo: newURL)
            let header = AudioMath.wavHeaderPCM16Mono(sampleRate: sampleRate, numSamples: 0)
            try h.write(contentsOf: header)
            handle = h
        } catch {
            logger
                .error(
                    "\(self.prefix, privacy: .public) audio file open failed: \(String(describing: error), privacy: .public)",
                )
            handle = nil
            url = nil
        }
    }

    /// Append a frame's worth of PCM16 bytes. Drops silently on write failure.
    func append(_ pcm16: Data) {
        guard let h = handle else { return }
        do {
            try h.write(contentsOf: pcm16)
            samplesWritten &+= UInt32(pcm16.count / MemoryLayout<Int16>.size)
        } catch {
            logger
                .error(
                    "\(self.prefix, privacy: .public) audio append failed: \(String(describing: error), privacy: .public)",
                )
        }
    }

    /// Patch the wav header's two size fields with the actual sample count, then close the handle. Header offsets per WAV RIFF spec: byte 4 = riff size (LE u32), byte 40 = data size (LE u32).
    func close() {
        guard let h = handle else { return }
        let samples = samplesWritten
        do {
            let dataBytes = samples * UInt32(MemoryLayout<Int16>.size)
            let riffSize = UInt32(36) + dataBytes
            try h.seek(toOffset: 4)
            try h.write(contentsOf: Data(littleEndian: riffSize))
            try h.seek(toOffset: 40)
            try h.write(contentsOf: Data(littleEndian: dataBytes))
            try h.close()
        } catch {
            logger
                .error(
                    "\(self.prefix, privacy: .public) audio close failed: \(String(describing: error), privacy: .public)",
                )
        }
        handle = nil
    }
}
