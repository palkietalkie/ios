import SwiftUI

extension EnvironmentValues {
    @Entry var micFrameReporter: (@MainActor @Sendable (CGRect) -> Void)?
}

/// Talk tab. Composes mic + status (tips during cold start, error retry on failure) + optional captions.
///
/// Single responsibility: layout the conversation screen and drive the SessionController lifecycle (start on appear, end on disappear). Captions UI lives in `CaptionsView.swift`; loading tips in `LoadingTipsView.swift`.
struct ConversationView: View {
    @Environment(SessionController.self) private var session
    @Environment(\.micFrameReporter) private var micFrameReporter
    /// Captions = on-screen text of what the AI is saying, in the same language as the audio. Off by default — the product is voice-first. User can toggle on per-session via the CC button below the mic. Persisted across sessions in UserDefaults.
    @AppStorage("captionsEnabled") private var captionsEnabled: Bool = false
    /// Render captions transliterated to Latin (romaji / pinyin) for learners who can't read the target's script yet. Persisted across sessions like captionsEnabled.
    @AppStorage("captionsRomanized") private var captionsRomanized: Bool = false
    @State private var showUpgrade = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mic + status are centered within their own flexible region.
                // Captions get a SEPARATE equal region below, so toggling CC only fills or empties the lower half — it never reflows the mic above (previously captions sat inside this stack and pushed the mic up when shown).
                VStack(spacing: 16) {
                    Spacer(minLength: 0)
                    micIndicator
                    statusContent
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)

                ZStack {
                    // Color.clear keeps this region claiming its half whether captions are shown or not — without it the empty region collapses and the mic above re-centers, which is the "mic jumps when I tap CC" bug.
                    Color.clear
                    // Keep the transcript visible after a cap (even with captions off) so dismissing the limit cover reveals the conversation the user just finished.
                    if captionsEnabled || session.reviewLastTranscript {
                        CaptionsScroll(transcript: session.transcript, romanized: captionsRomanized)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding()
            // CC toggle sits top-right (YouTube-style), out of the center column so it never crowds or moves the mic. Placed as an overlay rather than a `.toolbar` item so it doesn't get the iOS 26 Liquid-Glass capsule the toolbar draws behind items — we want only CaptionsToggle's own rect fill, no circular ring.
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 12) {
                    // Romanize toggle appears only when captions are showing AND actually contain a non-Latin script — a Spanish learner never sees a control that would do nothing.
                    if captionsEnabled || session.reviewLastTranscript,
                       session.transcript.contains(where: { hasNonLatinScript($0.text) })
                    {
                        CaptionsRomanizeToggle(romanized: $captionsRomanized)
                    }
                    CaptionsToggle(enabled: $captionsEnabled)
                }
                .padding()
            }
            .task {
                // AI starts the conversation the moment the screen appears — no button. If we land here mid-session, leave it alone. And don't restart into an instant 402 after the user hit their cap (even once they've dismissed the cover) — the window is spent until it resets.
                if session.phase == .idle, !session.reviewLastTranscript {
                    await session.start()
                }
            }
            .onDisappear {
                // Leaving the Talk tab (switching tabs or backgrounding) ends the session — no explicit end button. Fire end() whenever there could be an in-flight server session, not just on .live/.connecting: fast tab-switches caught the previous version in .startingSession (after POST /start landed but before WS upgrade completed), which left the session dangling — no /end posted, no post-session pipelines, no word_freq/phrase_freq rows.
                switch session.phase {
                case .gatheringContext, .startingSession, .connecting, .live, .reconnecting:
                    Task { await session.end() }
                case .idle, .ending, .error:
                    break
                }
            }
            // Out of free time: a full cover over the Talk view; "Not now" dismisses it to reveal the transcript underneath.
            .overlay {
                if session.endedOnFreeCapLimit {
                    FreeCapLimitView(
                        limitKind: session.freeCapLimitKind,
                        onUpgrade: FeatureFlags.subscriptionsEnabled ? { showUpgrade = true } : nil,
                        onDismiss: { session.endedOnFreeCapLimit = false },
                    )
                }
            }
            .sheet(isPresented: $showUpgrade) { SubscriptionView() }
        }
    }

    private var micIndicator: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 32))
            .frame(width: 80, height: 80)
            .background(micBackground)
            .foregroundStyle(.white)
            .clipShape(Circle())
            // React specifically to the tutor talking — swell + glow while the AI speaks, settle when it's the user's turn. Tied to `isAISpeaking` (driven by inbound AI transcript), not the generic `.live` phase, which stayed true for the whole session and so never actually animated to the conversation.
            .scaleEffect(session.isAISpeaking ? 1.12 : 1.0)
            .shadow(
                color: session.isAISpeaking ? Color.green.opacity(0.7) : .clear,
                radius: session.isAISpeaking ? 18 : 0,
            )
            .symbolEffect(.pulse, isActive: session.isAISpeaking)
            .animation(.spring(response: 0.35, dampingFraction: 0.5), value: session.isAISpeaking)
            // Report the mic's rendered frame so ConversationMicPositionTests can assert toggling CC never moves it. The reporter is nil in production; a clear GeometryReader in the background doesn't affect layout.
            .background(GeometryReader { proxy in
                Color.clear.onAppear { micFrameReporter?(proxy.frame(in: .global)) }
            })
    }

    private var micBackground: Color {
        switch session.phase {
        case .live: .green
        case .reconnecting: .orange
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
        case .reconnecting:
            VStack(spacing: 12) {
                ProgressView()
                Text("Reconnecting…")
                    .foregroundStyle(.secondary)
            }
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
