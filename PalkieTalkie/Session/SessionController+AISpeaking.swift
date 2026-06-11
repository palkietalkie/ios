import Foundation

/// The mic's "tutor is speaking" signal, split out of SessionController to keep that type within SwiftLint's body-length budget.
extension SessionController {
    /// Flip `isAISpeaking` on when an AI chunk arrives; schedule it back off after a quiet gap so the mic settles between the tutor's turns. Each new AI chunk pushes the off-switch back, so it stays lit through a continuous turn.
    func markAISpeaking(for chunk: TranscriptChunk) {
        guard chunk.speaker == .persona else { return }
        isAISpeaking = true
        aiSpeakingResetTask?.cancel()
        aiSpeakingResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.isAISpeaking = false
        }
    }
}
