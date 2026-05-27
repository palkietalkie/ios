import SwiftUI

/// The "More" tab — a hub for everything not on the Talk-first critical path. Profile, Integrations, and future
/// settings live here as nav links.
struct MorePanelView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    ProfileView()
                } label: {
                    Label("Profile", systemImage: "person.fill")
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
            }
            .navigationTitle("More")
        }
    }
}
