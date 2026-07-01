import CoreGraphics
@testable import PalkieTalkie
import XCTest

/// The Talk-view waveform's amplitude mapping (the rendered shell is exercised by ConversationMicPositionTests, which hosts ConversationView). Locks in that bars rest on a low flat line when the tutor is silent, grow with the real output level, and form a bounded, non-uniform wave — so the replacement for the old mic glyph reads as a voice waveform, never a flat block or an overflowing bar.
final class CenterIndicatorTests: XCTestCase {
    func testBarsRestLowAndFlatWhenSilent() {
        for index in 0 ..< CenterIndicator.barCount {
            for t in stride(from: 0.0, through: 3.0, by: 0.2) {
                XCTAssertEqual(
                    CenterIndicator.barAmplitude(level: 0, index: index, t: t), 0.12, accuracy: 0.0001,
                    "every bar rests at the same low line when the tutor is silent",
                )
            }
        }
    }

    func testBarsStayWithinFrameAtFullLevel() {
        for index in 0 ..< CenterIndicator.barCount {
            for t in stride(from: 0.0, through: 6.0, by: 0.05) {
                let amp = CenterIndicator.barAmplitude(level: 1, index: index, t: t)
                XCTAssertGreaterThanOrEqual(amp, 0.12, "never below the resting floor")
                XCTAssertLessThanOrEqual(amp, 1.0, "never exceeds the 80x80 frame")
            }
        }
    }

    func testLouderMeansTaller() {
        // At a fixed bar + instant, a higher output level yields a taller bar.
        let quiet = CenterIndicator.barAmplitude(level: 0.2, index: 2, t: 1.0)
        let loud = CenterIndicator.barAmplitude(level: 0.8, index: 2, t: 1.0)
        XCTAssertGreaterThan(loud, quiet, "bars grow with the tutor's output amplitude")
    }

    func testBarsAreNonUniformWhileSpeaking() {
        // The per-bar phase offset makes a wave, not a block: at one moment the bars differ.
        let t = 1.3
        let heights = (0 ..< CenterIndicator.barCount).map {
            CenterIndicator.barAmplitude(level: 0.7, index: $0, t: t)
        }
        let distinct = Set(heights.map { Int(($0 * 1000).rounded()) })
        XCTAssertGreaterThan(distinct.count, 1, "bars have different heights at once, reading as a waveform")
    }

    func testLevelIsClamped() {
        // A stray out-of-range level (peak > 1, or negative) can't push a bar past the frame or below the floor.
        XCTAssertLessThanOrEqual(CenterIndicator.barAmplitude(level: 5, index: 0, t: 0.4), 1.0)
        XCTAssertEqual(CenterIndicator.barAmplitude(level: -3, index: 0, t: 0.4), 0.12, accuracy: 0.0001)
    }
}
