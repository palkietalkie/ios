@testable import PalkieTalkie
import XCTest

/// Locks the autofill-junk rejection that keeps invalid input out of Clerk and off the founder's feed.
final class IsValidEmailFormatTests: XCTestCase {
    func testRejectsAutofillJunk() {
        // The exact strings iOS autofill dropped into the email field (reviewer + real attempts).
        XCTAssertFalse(isValidEmailFormat("Sign in with Apple"))
        XCTAssertFalse(isValidEmailFormat("Hide My Email"))
    }

    func testRejectsObviousNonEmails() {
        XCTAssertFalse(isValidEmailFormat(""))
        XCTAssertFalse(isValidEmailFormat("wes"))
        XCTAssertFalse(isValidEmailFormat("wes@gitauto"))
        XCTAssertFalse(isValidEmailFormat("wes @gitauto.ai"))
    }

    func testAcceptsRealEmails() {
        XCTAssertTrue(isValidEmailFormat("wes@gitauto.ai"))
        XCTAssertTrue(isValidEmailFormat("hnishio0105@gmail.com"))
    }
}
