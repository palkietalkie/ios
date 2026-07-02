import Observation

/// View-model for `RatingPromptView`: owns the star + comment state and the tap handlers so the flow (pick a star, optionally add a comment, Send) is unit-testable without rendering SwiftUI. We collect an optional comment from EVERYONE, not just unhappy users: a happy user's "love it, wish it did X" is the most useful feedback we get, and at this stage it's worth one extra tap. Sentiment only gates the destination, not whether we ask (see `RatingPolicy.routesToAppStore`, applied by the parent).
@MainActor
@Observable
final class RatingPromptViewModel {
    var rating = 0
    var comment = ""

    /// Called once the user taps Send. `comment` is nil when left blank.
    let onRate: (_ rating: Int, _ comment: String?) -> Void
    let onDismiss: () -> Void

    /// Guards against an accidental double-submit (e.g. double-tapping Send before the sheet dismisses) writing two identical rows seconds apart. A genuine re-rating later is a new prompt with a fresh view-model, so this only suppresses duplicates within one presentation.
    private var didSubmit = false

    init(
        onRate: @escaping (_ rating: Int, _ comment: String?) -> Void,
        onDismiss: @escaping () -> Void,
    ) {
        self.onRate = onRate
        self.onDismiss = onDismiss
    }

    /// The comment box + Send appear once any star is chosen (a rating is required before sending).
    var showsCommentBox: Bool {
        rating > 0
    }

    func selectStar(_ star: Int) {
        rating = star
    }

    func submit() {
        guard !didSubmit else { return }
        didSubmit = true
        onRate(rating, comment.isEmpty ? nil : comment)
    }

    func dismiss() {
        onDismiss()
    }
}
