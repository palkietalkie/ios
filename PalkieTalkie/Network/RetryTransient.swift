import Foundation

/// Whether a thrown error is a transient network hiccup worth retrying (connection dropped mid-flight, timeout, momentarily offline) rather than a real failure (auth, bad response). Pure + testable.
func isTransientNetworkError(_ error: Error) -> Bool {
    guard let urlError = error as? URLError else { return false }
    let transient: Set<URLError.Code> = [
        .networkConnectionLost, .timedOut, .notConnectedToInternet,
        .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
    ]
    return transient.contains(urlError.code)
}

/// Run `operation`, retrying on transient network errors up to `maxAttempts` total; non-transient errors throw immediately. A short-lived request (e.g. the WebRTC SDP handshake POST) shouldn't fail the whole session when a dropped connection recovers on a quick retry.
func retryTransient<T>(maxAttempts: Int = 3, _ operation: () async throws -> T) async throws -> T {
    var attempt = 0
    while true {
        attempt += 1
        do {
            return try await operation()
        } catch {
            if attempt >= maxAttempts || !isTransientNetworkError(error) { throw error }
        }
    }
}
