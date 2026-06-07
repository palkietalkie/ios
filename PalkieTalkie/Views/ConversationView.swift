import SwiftUI

/// Talk tab. Composes mic + status (tips during cold start, error retry on failure) + optional captions.
///
/// Single responsibility: layout the conversation screen and drive the SessionController lifecycle (start on appear,
/// end on disappear). Captions UI lives in `CaptionsView.swift`; loading tips in `LoadingTipsView.swift`.
struct ConversationView: View {
    @Environment(SessionController.self) private var session
    /// Captions = on-screen text of what the AI is saying, in the same language as the audio. Off by default — the
    /// product is voice-first. User can toggle on per-session via the CC button below the mic. Persisted across
    /// sessions in UserDefaults.
    @AppStorage("captionsEnabled") private var captionsEnabled: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                micIndicator
                CaptionsToggle(enabled: $captionsEnabled)
                statusContent
                Spacer()
                if captionsEnabled { CaptionsScroll(transcript: session.transcript) }
            }
            .padding()
            .task {
                // AI starts the conversation the moment the screen appears — no button. If we land here mid-session,
                // leave it alone.
                if session.phase == .idle {
                    await session.start()
                }
            }
            .onDisappear {
                // Leaving the Talk tab (switching tabs or backgrounding) ends the session — no explicit end button. Fire end() whenever there could be an in-flight server session, not just on .live/.connecting: fast tab-switches caught the previous version in .startingSession (after POST /start landed but before WS upgrade completed), which left the session dangling — no /end posted, no post-session pipelines, no word_freq/phrase_freq rows.
                switch session.phase {
                case .gatheringContext, .startingSession, .connecting, .live:
                    Task { await session.end() }
                case .idle, .ending, .error:
                    break
                }
            }
        }
    }

    private var micIndicator: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 32))
            .frame(width: 80, height: 80)
            .background(micBackground)
            .foregroundStyle(.white)
            .clipShape(Circle())
            .symbolEffect(.pulse, isActive: session.phase == .live)
    }

    private var micBackground: Color {
        switch session.phase {
        case .live: .green
        case .error: .red
        default: .blue
        }
    }

    /// Below-mic content: tips during cold start, error + retry on failure, empty otherwise.
    @ViewBuilder private var statusContent: some View {
        switch session.phase {
        case .gatheringContext, .startingSession, .connecting:
            LoadingTipsView()
                .transition(.opacity)
        case let .error(message):
            VStack(spacing: 12) {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Button("Try again") {
                    Task { await session.start() }
                }
                .buttonStyle(.bordered)
            }
            .transition(.opacity)
        default:
            EmptyView()
        }
    }
}
