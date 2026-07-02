@testable import PalkieTalkie
import XCTest

/// Locks the one thing that makes the Talk-screen crash survivable: an Objective-C NSException (which Swift's own do/catch cannot intercept, and which otherwise aborts the process with SIGABRT) must be converted into an ordinary Swift error that callers can catch.
///
/// This is the exact crash from build 28 TestFlight reports (Milshka: "the app doesn't work"; Ayumi: "crashes after switching screens"): `AVAudioInputNode.setVoiceProcessingEnabled` raised an NSException from deep in AVFAudio, the surrounding Swift `catch` never ran, and the app SIGABRT'd. If `ObjCException.catching` is ever replaced by a plain Swift do/catch, the first test below stops passing and starts crashing the whole test run, which is the point.
final class ObjCExceptionTests: XCTestCase {
    func testConvertsRaisedNSExceptionIntoSwiftError() {
        XCTAssertThrowsError(
            try ObjCException.catching {
                NSException(name: .genericException, reason: "boom", userInfo: nil).raise()
            },
        ) { error in
            XCTAssertTrue("\(error)".contains("boom"), "the exception reason should survive into the Swift error")
        }
    }

    func testRunsCleanBlockWithoutThrowing() throws {
        var ran = false
        try ObjCException.catching { ran = true }
        XCTAssertTrue(ran)
    }

    func testReraisesObjCExceptionName() {
        XCTAssertThrowsError(
            try ObjCException.catching {
                NSException(name: .invalidArgumentException, reason: "bad format", userInfo: nil).raise()
            },
        ) { error in
            let description = "\(error)"
            XCTAssertTrue(description.contains("bad format"))
        }
    }
}
