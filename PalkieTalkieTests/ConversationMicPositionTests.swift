import os
@testable import PalkieTalkie
import SwiftUI
import XCTest

/// Regression for "the mic jumps when I tap CC." Captions live in their own reserved region, so toggling them must not change the mic's vertical position. This renders ConversationView for real and compares the mic's center Y (reported via MicFramePreferenceKey) with captions off vs on.
@MainActor
final class ConversationMicPositionTests: XCTestCase {
    private func makeController() -> SessionController {
        SessionController(
            context: FakeContextGatherer(context: ConversationContext(
                localISOTime: "2026-01-01T00:00:00Z", timezone: "UTC", lat: nil, lon: nil, city: nil,
                calendarEvents: [],
            )),
            backend: FakeConversationBackend(
                startResponse: StartResponse(
                    sessionId: "s", textPrompt: "", voiceId: "", wsUrl: "",
                    provider: "personaplex", ephemeralToken: nil,
                    freeSecondsRemaining: nil,
                    freeLimitKind: nil,
                ),
                endResponse: EndResponse(sessionId: "s", durationSeconds: 0),
            ),
            micPermission: StubMicPermission(shouldThrow: false),
            streamerFactory: StubAudioStreamerFactory(streamer: FakeAudioStreamer()),
            sessionFactory: StubSessionFactory(session: FakePersonaPlexSession()),
        )
    }

    private func micFrame(captionsOn: Bool) async -> CGRect {
        UserDefaults.standard.set(captionsOn, forKey: "captionsEnabled")
        let controller = makeController()
        controller.phase = .live
        // OSAllocatedUnfairLock is Sendable, so the @Sendable reporter closure can capture it (no @unchecked).
        let box = OSAllocatedUnfairLock(initialState: CGRect.zero)
        await TestHosting.host(
            ConversationView()
                .environment(controller)
                .environment(\.micFrameReporter) { frame in box.withLock { $0 = frame } },
            settleMs: 400,
        )
        return box.withLock { $0 }
    }

    func testMicHeightUnchangedWhenTogglingCaptions() async {
        let off = await micFrame(captionsOn: false)
        let on = await micFrame(captionsOn: true)
        UserDefaults.standard.set(false, forKey: "captionsEnabled")
        XCTAssertNotEqual(off, .zero, "mic frame should have been reported by the preference")
        XCTAssertEqual(off.midY, on.midY, accuracy: 1.0, "tapping CC must not move the mic vertically")
    }
}
