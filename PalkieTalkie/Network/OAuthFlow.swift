import AuthenticationServices
import Foundation
import UIKit

enum OAuthError: Error {
    case invalidURL
    case userCancelled
    case sessionFailed(Error)
}

/// Drives ASWebAuthenticationSession from an actor so concurrent provider connects don't race the SFAuthSession
/// lifecycle. The session needs a presentation anchor — we look up the active key window scene at start time.
@MainActor
final class OAuthFlow: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthFlow()

    /// `palkietalkie://oauth/google` is the canonical redirect URI; scheme is `palkietalkie`.
    private static let callbackScheme = "palkietalkie"

    private var activeSession: ASWebAuthenticationSession?

    func start(authURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: Self.callbackScheme
            ) { callbackURL, error in
                if let error {
                    let asError = error as? ASWebAuthenticationSessionError
                    if asError?.code == .canceledLogin {
                        continuation.resume(throwing: OAuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: OAuthError.sessionFailed(error))
                    }
                    return
                }
                _ = callbackURL // backend already persisted the token; iOS just needs to know the flow finished
                continuation.resume()
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.activeSession = session
            if !session.start() {
                continuation.resume(throwing: OAuthError.sessionFailed(
                    NSError(
                        domain: "OAuthFlow",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Couldn't start session"]
                    )
                ))
            }
        }
    }

    nonisolated func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // ASWebAuthenticationSession invokes this on the main thread (delegate contract). The protocol stub is
        // nonisolated for SDK-vintage reasons, so we assert and hop in.
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive }
            let candidate = scenes.first
            let window = candidate?.windows.first(where: { $0.isKeyWindow }) ?? candidate?.windows.first
            if let window {
                return window
            }
            // Fallback: attach to whatever scene we can find so we don't trigger the iOS 26 deprecation by calling UIWindow() with no scene.
            guard let scene = candidate else {
                preconditionFailure("OAuth flow needs at least one UIWindowScene to anchor.")
            }
            return UIWindow(windowScene: scene)
        }
    }
}
