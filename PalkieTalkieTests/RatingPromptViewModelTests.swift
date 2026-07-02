@testable import PalkieTalkie
import XCTest

@MainActor
final class RatingPromptViewModelTests: XCTestCase {
    private func makeModel() -> (RatingPromptViewModel, rated: () -> (Int, String?)?, dismissed: () -> Bool) {
        var lastRated: (Int, String?)?
        var didDismiss = false
        let model = RatingPromptViewModel(
            onRate: { rating, comment in lastRated = (rating, comment) },
            onDismiss: { didDismiss = true },
        )
        return (model, { lastRated }, { didDismiss })
    }

    func testNoCommentBoxUntilAStarIsChosen() {
        let (model, _, _) = makeModel()
        XCTAssertFalse(model.showsCommentBox)
        model.selectStar(3)
        XCTAssertEqual(model.rating, 3)
        XCTAssertTrue(model.showsCommentBox)
    }

    func testSelectingAStarDoesNotSendOnItsOwn() {
        // Every rating now goes through Send so we always get the chance to collect a comment, even from happy users.
        let (model, rated, _) = makeModel()
        model.selectStar(5)
        XCTAssertNil(rated())
    }

    func testSubmitSendsRatingWithComment() {
        let (model, rated, _) = makeModel()
        model.selectStar(2)
        model.comment = "the tutor talks too fast"
        model.submit()
        let result = rated()
        XCTAssertEqual(result?.0, 2)
        XCTAssertEqual(result?.1, "the tutor talks too fast")
    }

    func testSubmitSendsNilForBlankComment() {
        let (model, rated, _) = makeModel()
        model.selectStar(5)
        model.submit()
        let result = rated()
        XCTAssertEqual(result?.0, 5)
        XCTAssertNil(result?.1)
    }

    func testDismissInvokesCallback() {
        let (model, _, dismissed) = makeModel()
        model.dismiss()
        XCTAssertTrue(dismissed())
    }

    func testDoubleSubmitOnlyFiresOnce() {
        // An accidental double-tap on Send (before the sheet dismisses) must not write two identical rating rows.
        var calls = 0
        let model = RatingPromptViewModel(onRate: { _, _ in calls += 1 }, onDismiss: {})
        model.selectStar(3)
        model.submit()
        model.submit()
        XCTAssertEqual(calls, 1)
    }
}
