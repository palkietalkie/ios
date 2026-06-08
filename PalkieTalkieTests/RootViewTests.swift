@testable import PalkieTalkie
import SwiftUI
import ViewInspector
import XCTest

@MainActor
final class RootViewTests: XCTestCase {
    /// First paint while gates are loading: ProgressView with "Loading…" caption. A refactor that defaults to a different placeholder would silently change the loading impression — the spinner is the only signal the user isn't stuck.
    func testInitialPaintRendersProgressView() throws {
        let sut = RootView()
        let progress = try sut.inspect().find(ViewType.ProgressView.self)
        XCTAssertNotNil(progress)
    }
}
