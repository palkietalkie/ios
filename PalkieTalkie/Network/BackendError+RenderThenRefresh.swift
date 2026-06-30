import Foundation
import OSLog

extension BackendError {
    /// Render-then-refresh: only a decode/contract failure (the API's JSON shape drifted) is worth replacing a screen's cached/empty content with an error. A slow, offline, timed-out, or HTTP-error refresh keeps what's already shown and is logged, not surfaced.
    var isContractFailure: Bool {
        if case .decoding = self { return true }
        return false
    }
}

/// Render-then-refresh classifier for a failed cached-content refresh: returns the message to surface, or `nil` to keep the cached/empty content. Only a contract drift surfaces; a slow, offline, timed-out, or HTTP-error refresh is logged and swallowed. One rule for every cached view so a failed refresh is classified the same everywhere.
func contentRefreshError(_ error: Error, refreshing subject: String, log logger: Logger) -> String? {
    if let backendError = error as? BackendError, backendError.isContractFailure {
        return backendError.localizedDescription
    }
    logger
        .error(
            "\(subject, privacy: .public) refresh failed, kept cached content: \(String(describing: error), privacy: .public)",
        )
    return nil
}
