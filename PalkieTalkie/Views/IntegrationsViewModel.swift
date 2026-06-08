import EventKit
import Foundation
import Observation

/// View-model for `IntegrationsView`. Owns connect/disconnect logic + state so each branch can be unit-tested. OAuth is hidden behind `OAuthStarting` so tests can drive the cancelled / 503 / 501 / generic-error catches without invoking the real ASWebAuthenticationSession.
@MainActor
@Observable
final class IntegrationsViewModel {
    var appleCalendarGranted: Bool = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    var googleConnected: Bool = false
    var outlookConnected: Bool = false
    var statusMessage: String?
    var isLoading: Bool = false

    @ObservationIgnored let oauth: any OAuthStarting

    init(oauth: any OAuthStarting = DefaultOAuthStarter()) {
        self.oauth = oauth
    }

    func requestCalendar() async {
        let store = EKEventStore()
        let granted = await (try? store.requestFullAccessToEvents()) ?? false
        appleCalendarGranted = granted
    }

    func connectGoogle(api: BackendAPI) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let connect = try await api.connectGoogleCalendar()
            guard let url = URL(string: connect.authUrl) else {
                statusMessage = "Backend returned an invalid auth URL."
                googleConnected = false
                return
            }
            try await oauth.start(authURL: url)
            await refreshIntegrations(api: api)
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

    func connectOutlook(api: BackendAPI) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let connect = try await api.connectOutlook()
            guard let url = URL(string: connect.authUrl) else {
                statusMessage = "Backend returned an invalid auth URL."
                outlookConnected = false
                return
            }
            try await oauth.start(authURL: url)
            await refreshIntegrations(api: api)
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

    func refreshIntegrations(api: BackendAPI) async {
        do {
            let providers = try await api.listIntegrations()
            googleConnected = providers.first(where: { $0.provider == "google" })?.connected ?? false
            outlookConnected = providers.first(where: { $0.provider == "outlook" })?.connected ?? false
        } catch {
            // Silent — connecting works without the list call succeeding.
        }
    }
}
