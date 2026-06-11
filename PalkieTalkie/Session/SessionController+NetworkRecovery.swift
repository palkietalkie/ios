import Foundation

/// Mid-conversation connectivity recovery — the "elevator" path. Split out of SessionController.swift to keep the orchestrator under the type-body limit; same cross-file-extension pattern as +ServerReady / +Recall.
extension SessionController {
    /// Starts the connectivity watcher for this session's lifetime. Idempotent: re-entered by every `start()` (including auto-reconnects) but only the first call launches the task — so the watcher spans drops rather than dying with each WS.
    func startNetworkMonitoringIfNeeded() {
        guard networkTask == nil else { return }
        let statuses = pathMonitor.statuses()
        networkTask = Task { [weak self] in
            for await isOnline in statuses {
                guard let self else { return }
                await handlePathChange(isOnline: isOnline)
            }
        }
    }

    /// Drives the drop → reconnect transitions. Offline mid-call tears the dead session down to `.reconnecting`; online while `.reconnecting` restarts. A failed restart lands in `.error` (manual "Try again"), so we don't auto-loop on non-network failures.
    func handlePathChange(isOnline: Bool) async {
        if isOnline {
            if phase == .reconnecting {
                await start()
            }
            return
        }
        switch phase {
        case .gatheringContext, .startingSession, .connecting, .live:
            await teardown()
            phase = .reconnecting
        case .idle, .ending, .error, .reconnecting:
            break
        }
    }

    func cancelNetworkMonitoring() {
        networkTask?.cancel()
        networkTask = nil
    }
}
