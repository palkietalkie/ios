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

    /// 4-5 stars go to the PUBLIC App Store prompt; 1-3 stay private (feedback straight to us), so we don't push unhappy users to leave public reviews.
    static func routesToAppStore(rating: Int) -> Bool {
        rating >= 4
    }
}

/// In-app "how's it going" prompt. Reports every rating to the backend (which Slacks it), routes happy users to the
/// App Store review prompt and unhappy ones to a private comment box. Presentation + StoreKit live in the parent.
struct RatingPromptView: View {
    /// Called once the user commits a rating. `comment` is only collected for low ratings.
    let onRate: (_ rating: Int, _ comment: String?) -> Void
    let onDismiss: () -> Void

    @State private var rating = 0
    @State private var comment = ""

    var body: some View {
        VStack(spacing: 24) {
            Text("How's Palkie Talkie so far?")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                ForEach(1 ... 5, id: \.self) { star in
                    Button {
                        rating = star
                        // 4-5: nothing more to say, send immediately and let the parent fire the App Store prompt.
                        if RatingPolicy.routesToAppStore(rating: star) {
                            onRate(star, nil)
                        }
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.largeTitle)
                            .foregroundStyle(star <= rating ? Color.yellow : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Low rating → keep it private: ask what's wrong and send that to us instead of the public store.
            if rating > 0, !RatingPolicy.routesToAppStore(rating: rating) {
                TextField("What would make it better?", text: $comment, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2 ... 4)
                Button("Send") {
                    onRate(rating, comment.isEmpty ? nil : comment)
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Maybe later") { onDismiss() }
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}
