@testable import PalkieTalkie
import SwiftUI
import ViewInspector
import XCTest

@MainActor
final class LoadingTipsViewTests: XCTestCase {
    /// Headline copy is the user's first signal that the wait is expected (not a hang). Pin the literal so a refactor doesn't quietly change it to something less reassuring.
    func testHeadlineReadsLoadingYourTutor() throws {
        let sut = LoadingTipsView(tips: ["any tip"])
        let texts = try sut.inspect().findAll(ViewType.Text.self)
        let strings = try texts.map { try $0.string() }
        XCTAssertTrue(strings.contains("Loading your tutor…"))
    }

    /// One of the provided tips renders. The shuffle picks order non-deterministically, so we assert at least one of the inputs appears — not the specific one.
    func testCurrentTipIsOneOfProvidedTips() throws {
        let tips = ["Native speakers say 'gonna'.", "Pause for breath at commas."]
        let sut = LoadingTipsView(tips: tips)
        let texts = try sut.inspect().findAll(ViewType.Text.self).compactMap { try? $0.string() }
        let intersection = Set(tips).intersection(Set(texts))
        XCTAssertFalse(intersection.isEmpty, "expected one of the provided tips to render; got \(texts)")
    }

    /// Empty-tips edge case: when the caller passes nil or an empty array, the view falls back to the bundled tip list. We can't assert the bundled content without coupling to it, but we CAN assert that no crash + the Tip label still renders (the structure stays valid).
    func testEmptyTipsArrayFallsBackToBundledList() throws {
        let sut = LoadingTipsView(tips: [])
        // Label("Tip", …) renders as a Label; if the fallback didn't run, the body would crash on shuffledTips[index % 0].
        XCTAssertNoThrow(try sut.inspect().find(ViewType.Label.self))
    }

    /// Nil tips argument also runs the bundled-list fallback.
    func testNilTipsArgumentFallsBackToBundledList() throws {
        let sut = LoadingTipsView(tips: nil)
        XCTAssertNoThrow(try sut.inspect().find(ViewType.Label.self))
    }

    /// Hosts LoadingTipsView so the `.task` rotation loop runs at least one iteration. Without hosting the task block never fires.
    func testHostsLoadingTipsViewRunsTaskRotation() async {
        await TestHosting.host(LoadingTipsView(tips: ["Tip A", "Tip B", "Tip C"]), settleMs: 300)
    }
}
