import SwiftUI

/// Decides WHEN to ask for a rating and WHERE a rating routes. Pure + testable, no UI / no StoreKit / no I/O.
enum RatingPolicy {
    /// Engagement is measured in cumulative CONVERSATION MINUTES, not session count.
    /// One long talk and many short ones that add up are equal "experience", so minutes is the honest measure of whether the user has used the app enough to have an opinion.
    /// Don't ask until the user has had this many total minutes of conversation (enough to have a real opinion, not a first-impression).
    static let firstAskMinutes = 60
    /// Space repeat prompts this far apart. Apple shows its App Store review prompt at most 3 times per 365 days and silently no-ops the rest, so ~365/3 days between asks lets us use ALL THREE yearly slots (each rating ≥4 fires requestReview) instead of wasting them by being conservative.
    static let reAskAfterDays = 120

    /// Ask when the user is engaged enough (≥ firstAskMinutes of conversation) AND we've either never asked or it's been ≥ reAskAfterDays since the last ask. `now` is injected for testability. No permanent suppression: raters get re-asked next cycle too (opinions shift), and Apple's own cap keeps it from spamming the store.
    static func shouldPrompt(totalMinutes: Int, lastPromptedAt: Date?, now: Date) -> Bool {
        guard totalMinutes >= firstAskMinutes else { return false }
        guard let last = lastPromptedAt else { return true }
        let secondsPerDay = 24.0 * 60 * 60
        return now.timeIntervalSince(last) >= Double(reAskAfterDays) * secondsPerDay
    }

    /// 4-5 stars also fire the PUBLIC App Store prompt; 1-3 stay private (their comment reaches only us), so we don't push unhappy users to leave public reviews. Note this gates the DESTINATION only — we collect an optional comment from every rating regardless.
    static func routesToAppStore(rating: Int) -> Bool {
        rating >= 4
    }
}

/// Apply a committed rating: ALWAYS hand it to `record` (we keep every rating's feedback, happy or not), and additionally fire the App Store review prompt only for ratings that route to the public store.
/// Extracted from the view so the "record everyone, prompt-store only the happy ones" gate is unit-testable instead of buried in a SwiftUI closure.
@MainActor
func commitRating(
    rating: Int,
    comment: String?,
    record: (_ rating: Int, _ comment: String?) -> Void,
    requestStoreReview: () -> Void,
) {
    record(rating, comment)
    if RatingPolicy.routesToAppStore(rating: rating) {
        requestStoreReview()
    }
}

/// In-app "how's it going" prompt: pick a star, optionally add a comment, Send.
/// Every rating + comment is reported to the backend (which Slacks it); 4-5 additionally surface Apple's App Store review prompt. Presentation + StoreKit live in the parent.
struct RatingPromptView: View {
    @State private var model: RatingPromptViewModel

    init(
        onRate: @escaping (_ rating: Int, _ comment: String?) -> Void,
        onDismiss: @escaping () -> Void,
    ) {
        _model = State(initialValue: RatingPromptViewModel(onRate: onRate, onDismiss: onDismiss))
    }

    /// Test seam: inject a pre-configured model (e.g. with a star already chosen) so the comment-box branch can be exercised.
    init(model: RatingPromptViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 24) {
            Text("How's Palkie Talkie so far?")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                ForEach(1 ... 5, id: \.self) { star in
                    Button {
                        model.selectStar(star)
                    } label: {
                        Image(systemName: star <= model.rating ? "star.fill" : "star")
                            .font(.largeTitle)
                            .foregroundStyle(star <= model.rating ? Color.yellow : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Collected from everyone once a star is picked; optional. Low ratings stay private, high ratings still also reach the public store via the parent's requestReview.
            if model.showsCommentBox {
                TextField("Anything you'd like to add?", text: $model.comment, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2 ... 4)
                Button("Send") {
                    model.submit()
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Maybe later") { model.dismiss() }
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}
