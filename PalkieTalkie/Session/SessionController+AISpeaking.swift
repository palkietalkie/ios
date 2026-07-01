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

    /// Live tutor output amplitude (0…1) for the Talk-view waveform, gated by isAISpeaking so the bars fall to their resting line the instant the turn ends (rather than holding the last buffer's level through the audio-drain tail). Reads the streamer's nonisolated `outputLevel` synchronously, so a per-frame view read is cheap.
    var aiOutputLevel: Float {
        isAISpeaking ? (audioStreamer?.outputLevel ?? 0) : 0
    }

    /// Suspend until the tutor finishes its current spoken turn (or a safety timeout), so a caller can let a goodbye play out instead of cutting it off. Gates on BOTH the transcript flag (isAISpeaking) AND the actual audio drain (player still has buffers): the transcript arrives well ahead of the audio, so isAISpeaking alone goes quiet too early.
    func waitForAIToFinishSpeaking(timeout: TimeInterval = 8) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let stillPlaying = await audioStreamer?.isOutputPlaying() ?? false
            if !isAISpeaking, !stillPlaying { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}
