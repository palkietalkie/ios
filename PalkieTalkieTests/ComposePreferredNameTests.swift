@testable import PalkieTalkie
import XCTest

final class ComposePreferredNameTests: XCTestCase {
    func testJoinsFirstAndLast() {
        XCTAssertEqual(composePreferredName(firstName: "Wes", lastName: "Nishio"), "Wes Nishio")
    }

    func testFirstOnly() {
        XCTAssertEqual(composePreferredName(firstName: "Wes", lastName: nil), "Wes")
        XCTAssertEqual(composePreferredName(firstName: "Wes", lastName: ""), "Wes")
    }

    func testLastOnly() {
        XCTAssertEqual(composePreferredName(firstName: nil, lastName: "Nishio"), "Nishio")
    }

    /// The bug this guards: Apple sign-in shares no name, so both are empty/nil — the result must be "" (ask the user), NEVER the email local-part like "hnishio0105".
    func testEmptyWhenNoName() {
        XCTAssertEqual(composePreferredName(firstName: nil, lastName: nil), "")
        XCTAssertEqual(composePreferredName(firstName: "", lastName: "  "), "")
    }
}
