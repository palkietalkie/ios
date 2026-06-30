import Foundation

/// Debounced, change-guarded auto-save, shared by the settings view-models (Profile, Practice) so the logic lives once instead of copy-pasted. The view-model owns one of these, calls `markSaved` whenever it loads or persists the form, and `schedule` on every edit.
///
/// The guard (current != lastSaved) is what makes auto-save safe: a programmatic load, the cache hydrate, and save's own re-load all leave the snapshot equal to the last-saved one, so they no-op instead of bouncing into a save loop. Only a real user edit differs and persists.
@MainActor
final class AutoSaver<Snapshot: Equatable> {
    private var lastSaved: Snapshot?
    private var task: Task<Void, Never>?

    /// Record the snapshot just loaded from or persisted to the server, so a later `schedule` with an equal snapshot no-ops.
    func markSaved(_ snapshot: Snapshot) {
        lastSaved = snapshot
    }

    /// Persist after `debounce` of quiet, but only when `loaded` and the snapshot actually changed since the last `markSaved`. A new edit cancels the pending save so a burst of keystrokes is one write.
    func schedule(
        current: Snapshot,
        loaded: Bool,
        debounce: Duration = .seconds(1),
        save: @escaping () async -> Void,
    ) {
        guard loaded, current != lastSaved else { return }
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await save()
        }
    }
}
