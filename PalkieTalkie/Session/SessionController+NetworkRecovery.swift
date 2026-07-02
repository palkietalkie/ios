import AVFoundation
import Foundation
import UIKit

/// One synthesizer for the app's lifetime: AVSpeechSynthesizer must outlive its utterance or playback cuts off mid-word.
/// MainActor-isolated because it's only ever touched from announceReconnectingIfUnseen() (itself on the MainActor SessionController), and AVSpeechSynthesizer isn't Sendable.
@MainActor private let reconnectCueSpeaker = AVSpeechSynthesizer()

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
            announceReconnectingIfUnseen()
            await markServerSessionEnded()
            await teardown()
            phase = .reconnecting
        case .idle, .ending, .error, .reconnecting:
            break
        }
    }

    /// The realtime transport died unexpectedly (socket/network error in the recv loop) WITHOUT NWPathMonitor reporting offline — the wifi→cellular handoff and "socket is not connected" cases the path-only watcher misses. Report it to the backend (the only server-side trace, since the audio WS is iOS↔provider direct), then drive the same drop→reconnect transition as a path loss. The network itself is usually fine here, so we attempt `start()` immediately; a failed restart lands in `.error` (manual retry) so we don't auto-loop on a hard failure.
    func handleTransportDisconnect(reason: String) async {
        switch phase {
        case .gatheringContext, .startingSession, .connecting, .live:
            announceReconnectingIfUnseen()
            await reportSessionError(reason: "transport disconnect: \(reason)")
            await markServerSessionEnded()
            await teardown()
            phase = .reconnecting
            await start()
        case .idle, .ending, .error, .reconnecting:
            break
        }
    }

    /// Speak a short cue when the user likely CAN'T see the orange "Reconnecting…" state — screen off or app backgrounded (in a pocket on a walk/commute, our core context). In the foreground the visible state already says it, so we stay silent to avoid nagging on every transient socket blip.
    func announceReconnectingIfUnseen() {
        guard Self.shouldAnnounceReconnect(appState: UIApplication.shared.applicationState) else { return }
        reconnectCueSpeaker.speak(AVSpeechUtterance(string: String(localized: "Connection lost. Reconnecting.")))
    }

    /// Pure, testable gate: announce only when the app isn't foreground-active, since the visible UI covers that case.
    static func shouldAnnounceReconnect(appState: UIApplication.State) -> Bool {
        appState != .active
    }

    func cancelNetworkMonitoring() {
        networkTask?.cancel()
        networkTask = nil
    }
}
