/// The single source of truth for which top-level screen `RootView` shows.
///
/// Pulled out of the view as a pure function for one reason: the sign-in flip bug. When the user has just signed in, the consent/profile gates are still `nil` (loading) — and an inline `if/else` chain falls through to the "everything passed" branch (`MainTabView`) until the gates resolve, flashing the wrong screen. Encoding "gates unknown → wait" as a value that can be unit-tested keeps that decision honest.
enum RootDestination: Equatable {
    case loading
    case signIn
    case consent
    case onboarding
    case main
}

/// `consentSet` / `profileComplete` are tri-state: `nil` = not loaded yet, `false` = gate not passed, `true` = passed. A signed-in user with any gate still `nil` lands on `.loading`, NOT `.main` — that flash-of-main-then-onboarding was the flip the user saw.
func resolveRootDestination(
    isLoading: Bool,
    userSignedIn: Bool,
    consentSet: Bool?,
    profileComplete: Bool?,
) -> RootDestination {
    if isLoading { return .loading }
    if !userSignedIn { return .signIn }
    guard let consentSet, let profileComplete else { return .loading }
    if !consentSet { return .consent }
    if !profileComplete { return .onboarding }
    return .main
}
