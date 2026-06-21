import ClerkKit
import SwiftUI

@main
struct PalkieTalkieApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let backendAPI: BackendAPI
    private let authing: any Authing
    private let pushNotifications: PushNotifications
    @State private var sessionController: SessionController
    /// App's display language. Empty string = follow iOS system. Otherwise BCP-47 code (e.g. "ja", "zh-Hans") that overrides via `.environment(\.locale, …)`. User picks in More → Language.
    @AppStorage("AppLocale") private var appLocale: String = ""

    init() {
        // Clerk v1.x fatal-errors on any `Clerk.shared` access before configure. Even unit-test runs evaluate the SwiftUI body (which touches Clerk.shared via RootView), so we always configure. The dev pk_test key passes Clerk's format validation; subsequent network calls under XCTest just fail without authenticating, which is what tests want.
        let key = Bundle.main.object(forInfoDictionaryKey: "CLERK_PUBLISHABLE_KEY") as? String ?? ""
        Clerk.configure(publishableKey: key)
        // Production wiring: real URLSession + Clerk-backed Authing. All views pull these out of `@Environment`. Tests construct their own and pass via `.environment(\.backendAPI, …)`.
        let transport = AppEnvironment.makeProductionTransport()
        let authing = ClerkAuthAdapter()
        let backendAPI = BackendAPI(transport: transport, auth: authing)
        self.backendAPI = backendAPI
        self.authing = authing
        pushNotifications = PushNotifications(backend: backendAPI)
        AppDelegate.pushNotifications = pushNotifications
        _sessionController = State(initialValue: SessionController(backend: backendAPI))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(sessionController)
                .environment(\.backendAPI, backendAPI)
                .environment(\.authing, authing)
                .environment(\.onboardingAnnouncer, AppEnvironment.makeProductionOnboardingAnnouncer())
                .environment(\.locale, appLocale.isEmpty ? .current : Locale(identifier: appLocale))
                .task {
                    try? AudioSessionManager.configureForFullDuplexVoice()
                    await pushNotifications.bootstrap()
                }
        }
    }
}
