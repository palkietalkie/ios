@testable import PalkieTalkie
import SwiftUI
import UIKit
import XCTest

/// ConversationView's body has a switch over SessionController.Phase that picks the mic background color, the status-content sub-view, and the symbol-effect. Default ViewBodyTests only hit the `.idle` branch; this file hosts the view with each phase set manually so the other branches are exercised.
@MainActor
final class ConversationViewBranchTests: XCTestCase {
    private func makeController() -> SessionController {
        SessionController(
            context: FakeContextGatherer(context: ConversationContext(
                localISOTime: "2026-01-01T00:00:00Z",
                timezone: "UTC", lat: nil, lon: nil,
                city: nil, weatherDescription: nil, temperatureC: nil,
                calendarEvents: [],
            )),
            backend: FakeConversationBackend(
                startResponse: StartResponse(
                    sessionId: "s", textPrompt: "", voiceId: "", wsUrl: "",
                    provider: "personaplex", ephemeralToken: nil,
                ),
                endResponse: EndResponse(sessionId: "s", durationSeconds: 0),
            ),
            micPermission: StubMicPermission(shouldThrow: false),
            streamerFactory: StubAudioStreamerFactory(streamer: FakeAudioStreamer()),
            sessionFactory: StubSessionFactory(session: FakePersonaPlexSession()),
        )
    }

    private func host(_ view: some View) async {
        await TestHosting.host(view, settleMs: 200)
    }

    func testConversationViewWithCaptionsEnabledRendersOverlay() async {
        // The CC toggle sits in a top-trailing overlay (not the toolbar) so it carries no Liquid-Glass capsule ring. With captions on, host the view to exercise that overlay branch + the captions region.
        UserDefaults.standard.set(true, forKey: "captionsEnabled")
        defer { UserDefaults.standard.removeObject(forKey: "captionsEnabled") }
        let controller = makeController()
        controller.phase = .live
        await host(ConversationView().environment(controller))
    }

    func testConversationViewLivePhase() async {
        let controller = makeController()
        controller.phase = .live
        await host(ConversationView().environment(controller))
    }

    func testConversationViewErrorPhase() async {
        let controller = makeController()
        controller.phase = .error("backend down")
        await host(ConversationView().environment(controller))
    }

    func testConversationViewGatheringContextPhase() async {
        let controller = makeController()
        controller.phase = .gatheringContext
        await host(ConversationView().environment(controller))
    }

    func testConversationViewConnectingPhase() async {
        let controller = makeController()
        controller.phase = .connecting
        await host(ConversationView().environment(controller))
    }

    func testConversationViewStartingSessionPhase() async {
        let controller = makeController()
        controller.phase = .startingSession
        await host(ConversationView().environment(controller))
    }

    func testConversationViewEndingPhase() async {
        let controller = makeController()
        controller.phase = .ending
        await host(ConversationView().environment(controller))
    }

    func testConversationViewReconnectingPhase() async {
        // Exercises the orange mic background + the "Reconnecting…" status sub-view added for mid-call network drops.
        let controller = makeController()
        controller.phase = .reconnecting
        await host(ConversationView().environment(controller))
    }

    func testConversationViewWithCaptionsOn() async {
        UserDefaults.standard.set(true, forKey: "captionsEnabled")
        let controller = makeController()
        controller.transcript = [
            TranscriptChunk(speaker: .persona, text: "Hi Wes"),
            TranscriptChunk(speaker: .user, text: "Hey"),
        ]
        controller.phase = .live
        await host(ConversationView().environment(controller))
        UserDefaults.standard.set(false, forKey: "captionsEnabled")
    }

    /// Phase enum has Equatable conformance; the .error case carries a String. Cover every branch of Phase comparison to exercise the synthesized Equatable.
    func testPhaseEquality() {
        XCTAssertEqual(SessionController.Phase.idle, SessionController.Phase.idle)
        XCTAssertNotEqual(SessionController.Phase.idle, SessionController.Phase.live)
        XCTAssertEqual(SessionController.Phase.error("x"), SessionController.Phase.error("x"))
        XCTAssertNotEqual(SessionController.Phase.error("x"), SessionController.Phase.error("y"))
    }
}
