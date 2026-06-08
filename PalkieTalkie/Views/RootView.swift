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
            if isLoading {
                ProgressView("Loading…")
            } else if clerk.user == nil {
                SignInView()
            } else if consentSet == false {
                ConsentView(onContinue: { consentSet = true })
            } else if profileComplete == false {
                OnboardingView(onContinue: { profileComplete = true })
            } else {
                MainTabView()
                    .task { await loadGatesIfNeeded() }
            }
        }
        .task { isLoading = false }
        .onChange(of: clerk.user?.id) { _, _ in
            consentSet = nil
            profileComplete = nil
            Task { await loadGatesIfNeeded() }
        }
    }

    private func loadGatesIfNeeded() async {
        if consentSet == nil {
            do {
                let current = try await api.getConsent()
                consentSet = current.set
            } catch {
                // If the backend isn't reachable, don't gate the user behind consent — fail open so they can still use the app. They'll see the screen on the next launch when the network recovers.
                consentSet = true
            }
        }
        if profileComplete == nil {
            do {
                let profile = try await api.getProfile()
                profileComplete = !profile.nativeLanguages.isEmpty && !profile.targetAccents.isEmpty
            } catch {
                // Same fail-open posture as consent — don't strand the user behind a sheet if the backend is unreachable.
                profileComplete = true
            }
        }
    }
}
