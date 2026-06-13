import ClerkKit
import Foundation

/// Turns a caught sign-in error into a string rich enough to debug a failure we CAN'T reproduce — a real user's in another country, or an App Review reviewer's — from the backend alone, with no device on a cable.
///
/// `error.localizedDescription` is useless for exactly the failures that matter: `ASAuthorizationError 1000 (.unknown)` renders as "The operation couldn't be completed" while the real cause sits one layer down in the `NSUnderlyingError` chain (an AuthKit `AKAuthenticationError` code), and a Clerk rejection hides its reason in `ClerkAPIError`'s structured fields. This is the string we ship to the backend as the failure `reason`, so it must carry those layers.
func diagnoseAuthError(_ error: Error) -> String {
    // Our own OAuth wrapper buries the real error in an associated value that NSError bridging would drop — unwrap it first.
    if let oauth = error as? OAuthError {
        switch oauth {
        case .invalidURL: return "OAuthError.invalidURL"
        case .userCancelled: return "OAuthError.userCancelled"
        case let .sessionFailed(inner): return capped("OAuthError.sessionFailed ← " + diagnoseAuthError(inner))
        }
    }
    // Clerk's API rejections name the real reason (e.g. an Apple token whose audience doesn't match the instance) in structured fields, not in localizedDescription.
    if let clerk = error as? ClerkAPIError {
        var parts = ["Clerk[\(clerk.code)]"]
        if let message = clerk.longMessage ?? clerk.message { parts.append(message) }
        if let trace = clerk.clerkTraceId { parts.append("trace=\(trace)") }
        return capped(parts.joined(separator: " "))
    }
    return capped(describeNSErrorChain(error as NSError))
}

/// Walk the `NSUnderlyingError` chain — `ASAuthorizationError 1000` and `ASWebAuthenticationSessionError 1` both wrap the lower-level error that actually names the cause.
private func describeNSErrorChain(_ error: NSError, depth: Int = 0) -> String {
    var line = "\(error.domain)#\(error.code): \(error.localizedDescription)"
    if let reason = error.userInfo[NSLocalizedFailureReasonErrorKey] as? String {
        line += " (\(reason))"
    }
    // Cap recursion: a malicious or cyclic chain shouldn't be able to blow the reason budget or loop.
    if depth < 4, let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
        line += " ← " + describeNSErrorChain(underlying, depth: depth + 1)
    }
    return line
}

/// Keep the reason under the backend's field limit so a long chain can never get the whole announce rejected (and the failure lost).
private func capped(_ value: String, max: Int = 1800) -> String {
    value.count <= max ? value : String(value.prefix(max)) + "…"
}
