import ClerkKit
import SwiftUI

struct RootView: View {
    @State private var clerk = Clerk.shared
    @State private var isLoading = true
    @State private var consentSet: Bool? =
        nil // nil = unknown / loading; false = needs first-launch screen; true = past the gate

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading…")
            } else if clerk.user == nil {
                SignInView()
            } else if consentSet == false {
                ConsentView(onContinue: { consentSet = true })
            } else {
                MainTabView()
                    .task { await loadConsentIfNeeded() }
            }
        }
        .task { isLoading = false }
        .onChange(of: clerk.user?.id) { _, _ in
            consentSet = nil
            Task { await loadConsentIfNeeded() }
        }
    }

    private func loadConsentIfNeeded() async {
        if consentSet != nil { return }
        do {
            let current = try await BackendAPI.shared.getConsent()
            consentSet = current.set
        } catch {
            // If the backend isn't reachable, don't gate the user behind consent — fail open so they can still use the
            // app. They'll see the screen on the next launch when the network recovers.
            consentSet = true
        }
    }
}
