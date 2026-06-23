import AVFoundation
import SwiftUI

/// Full-screen cover shown over the Talk view when a session ended on the free-plan cap. It names which window ran out (today vs this week, because the weekly block lasts until Monday and must read differently), speaks the same line aloud, and offers an upgrade. "Not now" dismisses it back to the Talk view, where the last transcript stays visible (the controller keeps showing it after a cap).
@MainActor
struct FreeCapLimitView: View {
    /// "daily" or "weekly" from the backend; anything else falls back to the daily wording.
    let limitKind: String?
    let onUpgrade: () -> Void
    let onDismiss: () -> Void

    private var isWeekly: Bool {
        limitKind == "weekly"
    }

    /// The spoken announcement, localized — same daily/weekly split as the on-screen title so the voice matches the text. On-device speech rather than a bundled clip: it localizes for free and ships no audio asset, and it's the guaranteed verbal cue even if the model skipped its in-character wrap-up.
    static func spokenLine(isWeekly: Bool) -> String {
        isWeekly
            ? String(localized: "Nice work this week!")
            : String(localized: "Nice work today!")
    }

    /// Shared so it isn't deallocated mid-utterance when the view redraws. The speech itself is audio-session / hardware bound and not unit-testable (like the rest of the audio path); only spokenLine's text selection is tested.
    private static let speaker = AVSpeechSynthesizer()

    private static func announce(isWeekly: Bool) {
        let utterance = AVSpeechUtterance(string: spokenLine(isWeekly: isWeekly))
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        speaker.speak(utterance)
    }

    /// Achievement framing, not a cutoff: the user practiced their whole free allowance, so celebrate it, then mention the reset + upgrade.
    private var title: LocalizedStringKey {
        isWeekly ? "Nice work this week!" : "Nice work today!"
    }

    private var detail: LocalizedStringKey {
        isWeekly
            ? "You've made the most of this week's free practice. It refreshes Monday, or upgrade for unlimited anytime."
            : "You've made the most of today's free practice. It refreshes tomorrow, or upgrade for unlimited anytime."
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hourglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onUpgrade) {
                Text("Upgrade").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Not now", action: onDismiss)
                .font(.subheadline)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .onAppear { Self.announce(isWeekly: isWeekly) }
    }
}
