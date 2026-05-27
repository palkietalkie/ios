import EventKit
import SwiftUI

struct IntegrationsView: View {
    @State private var appleCalendarGranted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    @State private var googleConnected = false
    @State private var outlookConnected = false
    @State private var statusMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                Section("Calendar") {
                    Toggle(isOn: $appleCalendarGranted) {
                        Label("Apple Calendar", systemImage: "calendar")
                    }
                    .onChange(of: appleCalendarGranted) { _, newValue in
                        if newValue { Task { await requestCalendar() } }
                    }
                    Toggle(isOn: $googleConnected) {
                        Label("Google Calendar", systemImage: "g.circle.fill")
                    }
                    .onChange(of: googleConnected) { _, newValue in
                        if newValue { Task { await connectGoogle() } }
                    }
                    Toggle(isOn: $outlookConnected) {
                        Label("Outlook", systemImage: "envelope.circle.fill")
                    }
                    .onChange(of: outlookConnected) { _, newValue in
                        if newValue { Task { await connectOutlook() } }
                    }
                }
                if let statusMessage {
                    Section { Text(statusMessage).font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Reminders") {
                    NavigationLink {
                        Text("Schedule recurring practice sessions — coming soon")
                    } label: {
                        Label("Practice schedule", systemImage: "alarm")
                    }
                }
            }
            .navigationTitle("Integrations")
            .task { await refreshIntegrations() }
            .overlay {
                if isLoading { ProgressView().padding().background(.regularMaterial).cornerRadius(8) }
            }
        }
    }

    private func requestCalendar() async {
        let store = EKEventStore()
        let granted = await (try? store.requestFullAccessToEvents()) ?? false
        await MainActor.run { appleCalendarGranted = granted }
    }

    private func connectGoogle() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let connect = try await BackendAPI.shared.connectGoogleCalendar()
            guard let url = URL(string: connect.authUrl) else {
                statusMessage = "Backend returned an invalid auth URL."
                googleConnected = false
                return
            }
            try await OAuthFlow.shared.start(authURL: url)
            await refreshIntegrations()
        } catch OAuthError.userCancelled {
            statusMessage = "Google sign-in cancelled."
            googleConnected = false
        } catch let BackendError.http(code, body) where code == 503 {
            statusMessage = "Google OAuth isn't configured on the server yet. (\(body))"
            googleConnected = false
        } catch {
            statusMessage = "Couldn't connect Google: \(error.localizedDescription)"
            googleConnected = false
        }
    }

    private func connectOutlook() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let connect = try await BackendAPI.shared.connectOutlook()
            guard let url = URL(string: connect.authUrl) else {
                statusMessage = "Backend returned an invalid auth URL."
                outlookConnected = false
                return
            }
            try await OAuthFlow.shared.start(authURL: url)
            await refreshIntegrations()
        } catch OAuthError.userCancelled {
            statusMessage = "Outlook sign-in cancelled."
            outlookConnected = false
        } catch let BackendError.http(code, _) where code == 501 {
            statusMessage = "Outlook integration coming soon."
            outlookConnected = false
        } catch {
            statusMessage = "Couldn't connect Outlook: \(error.localizedDescription)"
            outlookConnected = false
        }
    }

    private func refreshIntegrations() async {
        do {
            let providers = try await BackendAPI.shared.listIntegrations()
            await MainActor.run {
                googleConnected = providers.first(where: { $0.provider == "google" })?.connected ?? false
                outlookConnected = providers.first(where: { $0.provider == "outlook" })?.connected ?? false
            }
        } catch {
            // Silent — connecting works without the list call succeeding.
        }
    }
}
