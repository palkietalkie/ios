@testable import PalkieTalkie
import XCTest

final class WavAudioRecorderTests: XCTestCase {
    func testOpenCreatesFileWithHeaderAndExposesURL() throws {
        let r = WavAudioRecorder(prefix: "test-open", sampleRate: 24000)
        r.open()
        defer { cleanup(r) }
        guard let url = r.url else {
            XCTFail("url not set after open()")
            return
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        // 44-byte header should be on disk immediately.
        let bytes = try? Data(contentsOf: url)
        XCTAssertEqual(bytes?.count, 44)
        XCTAssertEqual(try String(data: XCTUnwrap(bytes?.prefix(4)), encoding: .ascii), "RIFF")
    }

    func testAppendIncrementsSamplesWrittenAndExtendsFile() {
        let r = WavAudioRecorder(prefix: "test-append", sampleRate: 24000)
        r.open()
        defer { cleanup(r) }
        let frame = Data(repeating: 0, count: 960) // 480 PCM16 samples
        r.append(frame)
        r.append(frame)
        XCTAssertEqual(r.samplesWritten, 960, "two 480-sample frames")
        if let url = r.url, let bytes = try? Data(contentsOf: url) {
            XCTAssertEqual(bytes.count, 44 + 1920)
        } else {
            XCTFail("file unreadable")
        }
    }

    func testCloseFixesUpRiffAndDataSizeFields() {
        let r = WavAudioRecorder(prefix: "test-close", sampleRate: 24000)
        r.open()
        defer { cleanup(r) }
        let frame = Data(repeating: 0xAA, count: 1000)
        r.append(frame)
        r.close()
        guard let url = r.url, let bytes = try? Data(contentsOf: url) else {
            XCTFail("file unreadable")
            return
        }
        // riff size at offset 4 (LE u32) = 36 + dataBytes; dataBytes = samplesWritten * 2.
        let samples = 500 // 1000 bytes / 2 bytes-per-sample
        let dataBytes = UInt32(samples) * 2
        let riffSize: UInt32 = 36 + dataBytes
        let riffBytes = bytes.subdata(in: 4 ..< 8)
        let riffParsed = riffBytes.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        XCTAssertEqual(riffParsed, riffSize)
        let dataChunkBytes = bytes.subdata(in: 40 ..< 44)
        let dataParsed = dataChunkBytes.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        XCTAssertEqual(dataParsed, dataBytes)
    }

    func testCloseWithoutOpenIsNoOp() {
        let r = WavAudioRecorder(prefix: "test-noop-close", sampleRate: 24000)
        r.close() // no crash, no file
        XCTAssertNil(r.url)
    }

    func testAppendBeforeOpenIsNoOp() {
        let r = WavAudioRecorder(prefix: "test-noop-append", sampleRate: 24000)
        r.append(Data(repeating: 0, count: 96))
        XCTAssertEqual(r.samplesWritten, 0)
    }

    func testOpenResetsSamplesWritten() {
        let r = WavAudioRecorder(prefix: "test-reopen", sampleRate: 24000)
        r.open()
        r.append(Data(repeating: 0, count: 200))
        XCTAssertGreaterThan(r.samplesWritten, 0)
        r.close()
        let oldURL = r.url
        r.open()
        defer { cleanup(r) }
        XCTAssertEqual(r.samplesWritten, 0)
        XCTAssertNotEqual(r.url?.lastPathComponent, oldURL?.lastPathComponent, "re-open uses fresh UUID")
        if let oldURL { try? FileManager.default.removeItem(at: oldURL) }
    }

    private func cleanup(_ r: WavAudioRecorder) {
        if let url = r.url {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
