import SwiftUI

/// The "More" tab — a hub for everything not on the Talk-first critical path. Profile, Practice, Integrations, and other settings live here as nav links.
///
/// Two attempts at restoring the last visited sub-screen (via `NavigationLink(value:)` + `NavigationStack(path:)`) broke every tap inside this tab — the destination would push then immediately bounce back. Reverted to direct-destination `NavigationLink {…} label:` form which works reliably. Sub-screen persistence dropped; top-level tab persistence still applies via `MainTabView`.
struct MorePanelView: View {
    @Environment(\.authing) private var auth

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ProfileView()
                } label: {
                    Label("Profile", systemImage: "person.fill")
                }
                NavigationLink {
                    PracticeView()
                } label: {
                    Label("Practice", systemImage: "graduationcap.fill")
                }
                NavigationLink {
                    IntegrationsView()
                } label: {
                    Label("Integrations", systemImage: "link")
                }
                NavigationLink {
                    PrivacyDataView()
                } label: {
                    Label("Privacy & Data", systemImage: "lock.shield")
                }
                NavigationLink {
                    LanguagePickerView()
                } label: {
                    Label("Display language", systemImage: "globe")
                }
                NavigationLink {
                    HistoryView()
                } label: {
                    Label("Past conversations", systemImage: "bubble.left.and.bubble.right")
                }
                if FeatureFlags.subscriptionsEnabled {
                    NavigationLink {
                        SubscriptionView()
                    } label: {
                        Label("Subscription", systemImage: "creditcard")
                    }
                }
                Section {
                    Button(role: .destructive) {
                        let auth = auth
                        Task { await auth.signOut() }
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("More")
        }
    }
}
