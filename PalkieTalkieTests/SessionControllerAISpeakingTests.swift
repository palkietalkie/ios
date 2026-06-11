@testable import PalkieTalkie
import XCTest

/// Pairs SessionController+AISpeaking.swift.
@MainActor
final class SessionControllerAISpeakingTests: XCTestCase {
    /// The mic animation keys off `isAISpeaking`, which must flip on when the tutor (a `.persona` chunk) speaks and auto-settle after a quiet gap.
    func testIsAISpeakingTracksPersonaTranscript() async {
        let rig = makeSessionControllerRig()
        await rig.controller.start()
        XCTAssertFalse(rig.controller.isAISpeaking)

        await rig.session.emit(transcript: TranscriptChunk(speaker: .persona, text: "Hey Wes", timestamp: Date()))
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(rig.controller.isAISpeaking, "tutor speaking should light the mic")

        // After the quiet-gap window (0.8s) with no new AI chunk, it settles.
        try? await Task.sleep(nanoseconds: 900_000_000)
        XCTAssertFalse(rig.controller.isAISpeaking, "mic should settle once the tutor stops")
    }
}
