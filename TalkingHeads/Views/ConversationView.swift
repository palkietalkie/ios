import SwiftUI

// TERMINOLOGY:
// - `struct ... : View` = A SwiftUI view component (like a React functional component).
//   The `body` property returns the UI tree (like JSX / render()).
// - `@EnvironmentObject` = Dependency injection from a parent view.
//   Like React Context — the parent provides it, children consume it.
// - `@State` = Local component state (like useState in React).
// - `.modifier()` methods chain onto views (like CSS-in-JS / Tailwind classes).
// - `VStack` = vertical flex container, `HStack` = horizontal flex container.
// - `ZStack` = layers views on top of each other (like position: absolute).

/// Main conversation screen — shows state indicator and transcript.
struct ConversationView: View {
    // Reads the VoiceOrchestrator from the environment (injected by parent)
    @EnvironmentObject var orchestrator: VoiceOrchestrator

    var body: some View {
        // `NavigationStack` = navigation container with a title bar (like React Router's layout)
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // State indicator — visual feedback for what the app is doing
                stateIndicator

                // Show last transcript and response
                if !orchestrator.lastTranscript.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("You", systemImage: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(orchestrator.lastTranscript)
                            .font(.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }

                if !orchestrator.lastResponse.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(orchestrator.selectedPersona?.name ?? "Tutor", systemImage: "bubble.left.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(orchestrator.lastResponse)
                            .font(.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }

                Spacer()

                // Start/stop button
                Button {
                    if orchestrator.state == .idle {
                        orchestrator.startConversation()
                    } else {
                        orchestrator.stopConversation()
                    }
                } label: {
                    // Circle button — tap to start, tap again to stop
                    Image(systemName: orchestrator.state == .idle ? "mic.fill" : "stop.fill")
                        .font(.system(size: 32))
                        .frame(width: 80, height: 80)
                        .background(orchestrator.state == .idle ? Color.blue : Color.red)
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("Talking Heads")
            // `toolbar` = top-right buttons in the navigation bar
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(destination: HistoryView()) {
                        Image(systemName: "clock")
                    }
                }
            }
        }
    }

    // `@ViewBuilder` lets you return multiple views conditionally (like fragments in React)
    @ViewBuilder
    private var stateIndicator: some View {
        switch orchestrator.state {
        case .idle:
            Text("Tap to start")
                .font(.title2)
                .foregroundStyle(.secondary)
        case .listening:
            // `withAnimation` = applies a transition animation (like CSS transitions)
            Label("Listening...", systemImage: "waveform")
                .font(.title2)
                .foregroundStyle(.blue)
                .symbolEffect(.variableColor.iterative)
        case .transcribing:
            Label("Transcribing...", systemImage: "text.bubble")
                .font(.title2)
                .foregroundStyle(.orange)
        case .thinking:
            Label("Thinking...", systemImage: "brain")
                .font(.title2)
                .foregroundStyle(.purple)
                .symbolEffect(.pulse)
        case .speaking:
            Label("Speaking...", systemImage: "speaker.wave.3.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .symbolEffect(.variableColor.iterative)
        }
    }
}
