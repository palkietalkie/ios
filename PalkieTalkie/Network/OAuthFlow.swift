import AuthenticationServices
import Foundation
import UIKit

enum OAuthError: Error {
    case invalidURL
    case userCancelled
    case sessionFailed(Error)
}

/// Minimal seam over `ASWebAuthenticationSession`. Production wires the real session through `DefaultWebAuthSessionFactory`; tests inject a `FakeWebAuthSessionFactory` that controls the callback timing without touching system UI.
protocol WebAuthSession {
    func start() -> Bool
}

@MainActor
protocol WebAuthSessionFactory {
    /// Returns a session whose `start()` will eventually invoke `completion(callbackURL, error)` on the calling thread. The factory owns the system-UI dependency so OAuthFlow itself stays testable.
    func makeSession(
        url: URL,
        callbackURLScheme: String,
        presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
        completion: @escaping @Sendable (URL?, Error?) -> Void,
    ) -> WebAuthSession
}

@MainActor
final class DefaultWebAuthSessionFactory: WebAuthSessionFactory {
    func makeSession(
        url: URL,
        callbackURLScheme: String,
        presentationContextProvider: ASWebAuthenticationPresentationContextProviding,
        completion: @escaping @Sendable (URL?, Error?) -> Void,
    ) -> WebAuthSession {
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: callbackURLScheme,
            completionHandler: completion,
        )
        session.presentationContextProvider = presentationContextProvider
        session.prefersEphemeralWebBrowserSession = false
        return RealWebAuthSession(session: session)
    }

    private final class RealWebAuthSession: WebAuthSession {
        let session: ASWebAuthenticationSession
        init(session: ASWebAuthenticationSession) {
            self.session = session
        }

        func start() -> Bool {
            session.start()
        }
    }
}

/// Drives an authentication flow through ASWebAuthenticationSession (in production) or a Fake (in tests). Concurrent provider connects don't race the session lifecycle because every `start()` call constructs and retains its own session.
@MainActor
final class OAuthFlow: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthFlow()

    /// `palkietalkie://oauth/google` is the canonical redirect URI; scheme is `palkietalkie`.
    private static let callbackScheme = "palkietalkie"

    private let factory: WebAuthSessionFactory
    private var activeSession: WebAuthSession?

    init(factory: WebAuthSessionFactory = DefaultWebAuthSessionFactory()) {
        self.factory = factory
        super.init()
    }

    func start(authURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let session = factory.makeSession(
                url: authURL,
                callbackURLScheme: Self.callbackScheme,
                presentationContextProvider: self,
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
            self.activeSession = session
            if !session.start() {
                continuation.resume(throwing: OAuthError.sessionFailed(
                    NSError(
                        domain: "OAuthFlow",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Couldn't start session"],
                    ),
                ))
            }
        }
    }

    nonisolated func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // ASWebAuthenticationSession invokes this on the main thread (delegate contract). The protocol stub is nonisolated for SDK-vintage reasons, so we assert and hop in.
        MainActor.assumeIsolated { Self.presentationAnchorMainActor() }
    }

    /// Extracted so it's reachable from tests (the protocol method is nonisolated and tied to the SDK type).
    @MainActor
    static func presentationAnchorMainActor() -> ASPresentationAnchor {
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
