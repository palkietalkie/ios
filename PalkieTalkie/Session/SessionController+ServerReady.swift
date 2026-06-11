import Foundation

/// Server-ready timeout race, split out of SessionController to keep that type within SwiftLint's body-length budget.
extension SessionController {
    enum SessionStartError: LocalizedError {
        case serverReadyTimeout

        var errorDescription: String? {
            switch self {
            case .serverReadyTimeout:
                String(localized: "Couldn't reach your tutor. Tap to try again.")
            }
        }
    }

    /// Race `realtime.waitForServerReady()` against a wall-clock timeout. Returns true if the server signalled ready first, false on timeout. The provider clients park a NON-cancellable continuation inside `waitForServerReady`, so we can't cancel that wait — instead we ignore its late completion (the timeout already resolved us) and let `teardown()`'s `close()` drain the orphaned waiter cleanly.
    func awaitServerReady(_ realtime: RealtimeClient, timeoutSeconds: Double) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            serverReadyContinuation = cont
            Task { [weak self] in
                await realtime.waitForServerReady()
                self?.resolveServerReady(true)
            }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                self?.resolveServerReady(false)
            }
        }
    }

    func resolveServerReady(_ ready: Bool) {
        guard let cont = serverReadyContinuation else { return }
        serverReadyContinuation = nil
        cont.resume(returning: ready)
    }
}
