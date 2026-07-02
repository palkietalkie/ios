/// Tracks the OpenAI response lifecycle so the free-cap wind-down never races an in-flight reply. OpenAI rejects a second `response.create` while one is active, which would drop the goodbye, so a wind-down requested mid-reply is deferred until the active reply's `response.done` and fired then. Pure + testable; OpenAIWebRTCClient holds it behind a lock (touched from the data-channel thread and the MainActor).
struct ResponseLifecycle {
    private(set) var active = false
    private var pendingWindDown = false

    mutating func onResponseCreated() {
        active = true
    }

    /// The in-flight reply finished. Returns true if a deferred wind-down should now fire its `response.create`.
    mutating func onResponseDone() -> Bool {
        active = false
        defer { pendingWindDown = false }
        return pendingWindDown
    }

    /// A wind-down (free-cap goodbye) was requested. Returns true to fire `response.create` now, false if it was deferred until the in-flight reply finishes.
    mutating func onWindDownRequested() -> Bool {
        if active {
            pendingWindDown = true
            return false
        }
        return true
    }
}
