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

    func testFromExceptionMapsNameReasonAndKind() {
        let exception = NSException(name: .genericException, reason: "boom", userInfo: nil)
        let record = CrashRecord.fromException(exception, build: "29", at: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(record.kind, "nsexception")
        XCTAssertEqual(record.name, "NSGenericException")
        XCTAssertEqual(record.reason, "boom")
        XCTAssertEqual(record.build, "29")
    }

    func testFromExceptionWithNilReasonIsEmptyString() {
        let exception = NSException(name: .rangeException, reason: nil, userInfo: nil)
        XCTAssertEqual(CrashRecord.fromException(exception, build: "29", at: Date()).reason, "")
    }

    func testFromSignalNamesTheSignalAndKeepsTopFrame() {
        let symbols = ["6   PalkieTalkie  0x1 Foo.bar() + 4 (Foo.swift:9)"]
        let record = CrashRecord.fromSignal(SIGABRT, symbols: symbols, build: "29", at: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(record.kind, "signal")
        XCTAssertEqual(record.name, "SIGABRT")
        XCTAssertEqual(record.reason, "fatal signal 6")
        XCTAssertEqual(record.topFrame, "Foo.bar() + 4 (Foo.swift:9)")
    }

    func testSignalNameKnownAndUnknown() {
        XCTAssertEqual(CrashRecord.signalName(SIGSEGV), "SIGSEGV")
        XCTAssertEqual(CrashRecord.signalName(SIGILL), "SIGILL")
        XCTAssertEqual(CrashRecord.signalName(SIGTRAP), "SIGTRAP")
        XCTAssertEqual(CrashRecord.signalName(SIGBUS), "SIGBUS")
        XCTAssertEqual(CrashRecord.signalName(SIGFPE), "SIGFPE")
        XCTAssertEqual(CrashRecord.signalName(99), "SIG99")
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
