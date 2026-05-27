import ClerkKit
import SwiftUI

@main
struct PalkieTalkieApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var sessionController = SessionController()

    init() {
        // Clerk v1.x fatal-errors on any `Clerk.shared` access before configure. Must run before any View struct (e.g.
        // RootView with @State Clerk.shared) is built.
        let key = Bundle.main.object(forInfoDictionaryKey: "CLERK_PUBLISHABLE_KEY") as? String ?? ""
        Clerk.configure(publishableKey: key)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(sessionController)
                .task {
                    try? AudioSessionManager.configureForFullDuplexVoice()
                    await PushNotifications.shared.bootstrap()
                }
        }
    }
}
