import Foundation

/// Transcript turn-buffering: aggregate same-speaker stream fragments into one turn, flush as a single `transcripts` row on speaker switch or session end. Split out of SessionController so the core file stays the phase machine + lifecycle.
@MainActor
extension SessionController {
    func appendTranscript(_ chunk: TranscriptChunk) {
        transcript.append(chunk)
        markAISpeaking(for: chunk)
        // Aggregate stream fragments into turn rows. Speaker switch (or session end) flushes the in-flight buffer as one POST → one DB row. Fragments from the same speaker join into one turn's text.
        if let pending = pendingTurn, pending.speaker == chunk.speaker {
            pendingTurn?.text += chunk.text
        } else {
            flushPendingTurn(endedAt: chunk.timestamp)
            pendingTurn = TurnBuffer(speaker: chunk.speaker, text: chunk.text, startedAt: chunk.timestamp)
        }
    }

    /// POSTs the in-flight turn buffer as one transcripts row. Called on speaker switch and on session end.
    /// Fire-and-forget: dropped POST = a missing turn row, not a corrupted one.
    func flushPendingTurn(endedAt: Date) {
        guard let pending = pendingTurn, let sessionId = serverSessionId else { return }
        pendingTurn = nil
        let backend = backend
        Task {
            try? await backend.appendTranscript(
                sessionId: sessionId,
                speaker: pending.speaker.rawValue,
                text: pending.text,
                startedAt: pending.startedAt,
                endedAt: endedAt,
            )
        }
    }
}
