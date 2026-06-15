import AuthenticationServices
import Foundation

/// True when a sign-in error is the user backing out — closing the OAuth web sheet, tapping Cancel on the Apple sheet — rather than a broken flow. These must be treated as a no-op: a cancel is a choice, so it should NOT show an error to the user or fire the founder's `@channel` "broken funnel" alert. (Google sign-in surfaced exactly this as `WebAuthenticationSession error 1` and spammed the channel.)
func isUserCancellation(_ error: Error) -> Bool {
    if case OAuthError.userCancelled = error { return true }
    let ns = error as NSError
    if ns.domain == ASWebAuthenticationSessionError.errorDomain,
       ns.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
    {
        return true
    }
    if ns.domain == ASAuthorizationError.errorDomain, ns.code == ASAuthorizationError.Code.canceled.rawValue {
        return true
    }
    return false
}
