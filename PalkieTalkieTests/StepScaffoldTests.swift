@testable import PalkieTalkie
import SwiftUI
import ViewInspector
import XCTest

@MainActor
final class StepScaffoldTests: XCTestCase {
    /// The scaffold's whole reason to exist is surfacing the step's title + "why" reason. Pin that both render, so a refactor can't silently drop the reason line (which is what keeps users from abandoning an opaque field).
    func testRendersTitleAndWhy() throws {
        let sut = StepScaffold(title: "Pick a level", why: "So your tutor pitches it right") {
            Text(verbatim: "CONTENT")
        }
        let strings = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        XCTAssertTrue(strings.contains("Pick a level"))
        XCTAssertTrue(strings.contains("So your tutor pitches it right"))
    }

    /// The caller's content is embedded verbatim below the header.
    func testRendersProvidedContent() throws {
        let sut = StepScaffold(title: "t", why: "w") { Text(verbatim: "MY_CONTENT") }
        let strings = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        XCTAssertTrue(strings.contains("MY_CONTENT"))
    }
}
