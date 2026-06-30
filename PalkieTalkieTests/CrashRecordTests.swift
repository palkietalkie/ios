@testable import PalkieTalkie
import XCTest

final class CrashRecordTests: XCTestCase {
    func testTopAppFrameKeepsSymbolAndSourceDropsAddress() {
        let stack = [
            "0   CoreFoundation     0x18417623c __exceptionPreprocess + 164",
            "3   AVFAudio           0x1bd3da2f4 AVAudioEngineGraph::_Connect(...) + 332",
            "6   PalkieTalkie       0x100e79cac RealInputNode.setVoiceProcessingEnabled(_:) + 64 (AudioEngineProtocol.swift:99)",
        ]
        XCTAssertEqual(
            CrashRecord.topAppFrame(from: stack),
            "RealInputNode.setVoiceProcessingEnabled(_:) + 64 (AudioEngineProtocol.swift:99)",
        )
    }

    func testTopAppFrameIsEmptyWhenNoAppFrame() {
        let stack = [
            "0   CoreFoundation     0x18417623c __exceptionPreprocess + 164",
            "3   AVFAudio           0x1bd3da2f4 AVAudioEngineGraph::_Connect(...) + 332",
        ]
        XCTAssertEqual(CrashRecord.topAppFrame(from: stack), "")
    }

    func testCodableRoundTrip() throws {
        let record = CrashRecord(
            kind: "nsexception",
            name: "NSGenericException",
            reason: "boom",
            topFrame: "Foo.bar (Foo.swift:1)",
            stack: ["a", "b"],
            build: "28",
            crashedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(CrashRecord.self, from: data)
        XCTAssertEqual(decoded, record)
    }
}
