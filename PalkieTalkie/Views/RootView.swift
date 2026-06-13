import ClerkKit
import SwiftUI

struct RootView: View {
    @Environment(\.backendAPI) private var api
    @State private var clerk = Clerk.shared
    @State private var isLoading = true
    @State private var consentSet: Bool? = nil
    /// nil = unknown / loading; false = needs onboarding sheet; true = past the gate.
    @State private var profileComplete: Bool? = nil

    var body: some View {
        Group {
            switch resolveRootDestination(
                isLoading: isLoading,
                userSignedIn: clerk.user != nil,
                consentSet: consentSet,
                profileComplete: profileComplete,
            ) {
            case .loading:
                ProgressView("Loading…")
            case .signIn:
                SignInView()
            case .consent:
                ConsentView(onContinue: { consentSet = true })
            case .onboarding:
                OnboardingView(onContinue: { profileComplete = true })
            case .main:
                MainTabView()
            }
        }
        .task { isLoading = false }
        // ONE loader keyed to the signed-in user: it cancels + re-runs on sign-in/out, so there's never a second concurrent load racing the first (the old `.onChange` + `MainTabView.task` pair did, which is what made the screen flip).
        .task(id: clerk.user?.id) { await resolveGates() }
    }

    private func resolveGates() async {
        guard clerk.user != nil else { return }
        // Clear any prior user's gate values up front so the user lands on `.loading` until THIS user's gates are fetched, never on a stale `.main`.
        consentSet = nil
        profileComplete = nil
        do {
            consentSet = try await api.getConsent().set
        } catch {
            // Fail open: a backend hiccup must not strand the user behind the consent gate; they'll see it next launch when the network recovers.
            consentSet = true
        }
        do {
            let profile = try await api.getProfile()
            profileComplete = !profile.nativeLanguages.isEmpty && !profile.targetAccents.isEmpty
        } catch {
            profileComplete = true
        }
    }
}
