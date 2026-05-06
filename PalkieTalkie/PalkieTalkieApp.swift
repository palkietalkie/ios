import SwiftData
import SwiftUI

// TERMINOLOGY:
// - `@main` = marks the app entry point (like `if __name__ == "__main__"` in Python).
// - `App` protocol = the top-level application struct.
//   SwiftUI apps don't have an AppDelegate by default — this struct IS the app.
// - `WindowGroup` = creates a window. On iPhone there's only one window.
// - `.modelContainer` = sets up the SwiftData database (SQLite under the hood).
//   All child views can then read/write data via @Query and @Environment(\.modelContext).
// - `.environmentObject` = injects a shared object into the view tree.
//   Any child view can access it via @EnvironmentObject (like React Context.Provider).
// - `.task` = runs an async function when the view appears (like useEffect in React).

@main
struct PalkieTalkieApp: App {
    // `@StateObject` = creates and owns an observable object for the lifetime of this view.
    // Like useRef + useState combined — persists across re-renders, owned by this component.
    @StateObject private var orchestrator = VoiceOrchestrator()

    var body: some Scene {
        WindowGroup {
            ConversationView()
                .environmentObject(orchestrator)
                .task {
                    // Pre-warm all models on launch (runs once when view appears)
                    await orchestrator.prepare()
                }
        }
        // Set up the SwiftData database with our model types
        // `for:` takes the model classes to create tables for
        .modelContainer(for: [Conversation.self, Message.self]) { result in
            switch result {
            case .success(let container):
                // Give the orchestrator access to the database
                Task { @MainActor in
                    orchestrator.configure(modelContext: container.mainContext)
                }
            case .failure(let error):
                print("[App] Failed to create model container: \(error)")
            }
        }
    }
}
