import OSLog

private let logger = Logger(subsystem: "com.palkietalkie", category: "freecap")

/// Free-plan mid-session enforcement: warn near the cap, hard-stop at it, and flag the end so the UI can explain it. Split out of SessionController so the core file stays the phase machine + lifecycle.
@MainActor
extension SessionController {
    /// Schedule a wrap-up hint at `remaining - 30s` and a hard end at `remaining`, driven by the precise `freeSecondsRemaining` the /start call returned (the SAME computation that authorized the session).
    /// nil = premium / unlimited, so no timers.
    /// Using the authoritative seconds fixes the old bug where a separate minute-granular entitlement fetch floored a sub-minute remainder to 0 and ended the session immediately with no wrap-up ("just ended without any notice").
    func scheduleFreeCapWrapUp(
        realtime: RealtimeClient, freeSecondsRemaining: Int?, freeLimitKind: String?,
    ) {
        guard let remainingSec = freeSecondsRemaining, remainingSec > 0 else { return }
        let warnAt = max(remainingSec - 30, 5)
        let hintTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(warnAt) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await realtime.injectSystemHint(
                "You have about 30 seconds left in this conversation before the user's free-plan limit ends the call. Wrap up naturally and warmly — a quick goodbye that fits your character. Don't ask new questions.",
            )
            await self?.logFreeCapEvent(stage: "warn", secondsRemaining: 30)
        }
        let endTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remainingSec) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.logFreeCapEvent(stage: "hard_end", secondsRemaining: 0)
            await self?.endOnFreeCapLimit(kind: freeLimitKind)
        }
        freeCapTasks = [hintTask, endTask]
    }

    /// The free-cap hard-stop fired. Flag it (and which cap) so the UI can explain what happened and play the limit announcement, then tear down like any other end.
    private func endOnFreeCapLimit(kind: String?) async {
        endedOnFreeCapLimit = true
        reviewLastTranscript = true
        freeCapLimitKind = kind
        // Local notification covers the backgrounded case (screen off on a walk), where the in-app card is invisible.
        notifyFreeCapReached(isWeekly: kind == "weekly")
        await end()
    }

    private func logFreeCapEvent(stage: String, secondsRemaining: Int) {
        logger.error("free-cap \(stage, privacy: .public) — \(secondsRemaining, privacy: .public)s remaining")
    }
}
