@testable import PalkieTalkie
import XCTest

@MainActor
final class VoicePreviewPlayerTests: XCTestCase {
    /// `availableVoiceIds` is consumed by both the picker (gates the "preview" button) and the catalog (knows which voices ship with a sample). A drift here silently hides preview affordances. Locking the explicit set.
    func testAvailableVoiceIdsMatchesBundledSamples() {
        XCTAssertEqual(
            VoicePreviewPlayer.availableVoiceIds,
            ["alloy", "ash", "coral", "echo", "sage", "shimmer"],
        )
    }

    /// `hasPreview` must accept any-case voice id — the iOS picker passes the raw catalog id (lowercase), but persona-customize allows the user to pick a custom voice that may carry uppercase characters. Case-folding here is the contract.
    func testHasPreviewIsCaseInsensitive() {
        XCTAssertTrue(VoicePreviewPlayer.hasPreview("Alloy"))
        XCTAssertTrue(VoicePreviewPlayer.hasPreview("CORAL"))
        XCTAssertTrue(VoicePreviewPlayer.hasPreview("echo"))
    }

    func testHasPreviewRejectsUnknownVoices() {
        XCTAssertFalse(VoicePreviewPlayer.hasPreview("ballad"))
        XCTAssertFalse(VoicePreviewPlayer.hasPreview("cedar"))
        XCTAssertFalse(VoicePreviewPlayer.hasPreview(""))
    }

    /// Fresh player has nothing playing. Lock the initial state so a refactor that adds eager-preload doesn't silently kick off playback.
    func testInitializesWithNoActivePlayback() {
        let p = VoicePreviewPlayer()
        XCTAssertNil(p.nowPlaying)
    }

    /// `play(voiceId:)` is a no-op when the voice has no bundled preview. The UI relies on this — tapping a row for a voice without a sample must NOT set `nowPlaying`, because the row's affordance would change and confuse the user.
    func testPlayIsNoOpForUnavailableVoice() {
        let p = VoicePreviewPlayer()
        p.play(voiceId: "ballad")
        XCTAssertNil(p.nowPlaying)
    }

    /// `stop()` always clears `nowPlaying` even when nothing was playing. Without this, a refactor that early-returns on a nil player would leave `nowPlaying` stale and the UI would never reset.
    func testStopAlwaysClearsNowPlaying() {
        let p = VoicePreviewPlayer()
        p.stop()
        XCTAssertNil(p.nowPlaying)
    }

    /// Real wav playback — the bundle ships alloy/ash/coral/echo/sage/shimmer wavs in Resources/VoiceSamples. play() should resolve the URL, init AVAudioPlayer, and set nowPlaying.
    func testPlayAvailableVoiceSetsNowPlayingAndSchedulesReset() {
        let p = VoicePreviewPlayer()
        p.play(voiceId: "alloy")
        XCTAssertEqual(p.nowPlaying, "alloy", "nowPlaying should advance to the voice id")
        // The reset Task waits for the sample duration; we just stop() so the test doesn't run for ~4s.
        p.stop()
        XCTAssertNil(p.nowPlaying)
    }

    /// Case-insensitive — uppercase "ALLOY" lowercases to "alloy" → resolves the bundled wav and sets nowPlaying.
    func testPlayUppercaseIdLowercasesAndSetsNowPlaying() {
        let p = VoicePreviewPlayer()
        p.play(voiceId: "ALLOY")
        XCTAssertEqual(p.nowPlaying, "ALLOY", "nowPlaying preserves the caller's id; only the bundle lookup lowercases")
        p.stop()
    }

    /// Calling play() a second time stops the first player and starts the new one.
    func testPlaySecondVoiceReplacesFirst() {
        let p = VoicePreviewPlayer()
        p.play(voiceId: "alloy")
        XCTAssertEqual(p.nowPlaying, "alloy")
        p.play(voiceId: "coral")
        XCTAssertEqual(p.nowPlaying, "coral")
        p.stop()
    }
}
