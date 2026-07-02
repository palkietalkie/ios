@testable import PalkieTalkie
import XCTest

final class NearFieldGateTests: XCTestCase {
    private let frameLen = 480 // 20ms @ 24kHz, matches AudioStreamer.frameSamples

    /// A voiced-speech proxy: a low-frequency sine. Crosses zero ~2f/24000 per sample, so ZCR stays well under the voicedness threshold.
    private func sine(freq: Float, amplitude: Float) -> [Float] {
        (0 ..< frameLen).map { i in
            amplitude * sin(2 * .pi * freq * Float(i) / 24000)
        }
    }

    /// A loud broadband-noise proxy: sign flips every sample, so ZCR ≈ 1.0 (far above any speech) while RMS is high.
    private func alternating(amplitude: Float) -> [Float] {
        (0 ..< frameLen).map { i in i % 2 == 0 ? amplitude : -amplitude }
    }

    /// A realistic voiced-speech frame at an exact level: a fundamental plus two harmonics (low ZCR, passes voicedness), normalized to the target dBFS. Lets preserve tests use real speech levels (normal ≈ -20 dBFS, soft ≈ -30, loud ≈ -10).
    private func speechFrame(dbfs: Float) -> [Float] {
        let f0: Float = 150
        var s = (0 ..< frameLen).map { i -> Float in
            let t = Float(i) / 24000
            return sin(2 * .pi * f0 * t) + 0.5 * sin(2 * .pi * 2 * f0 * t) + 0.33 * sin(2 * .pi * 3 * f0 * t)
        }
        let rms = (s.map { $0 * $0 }.reduce(0, +) / Float(s.count)).squareRoot()
        let target = pow(10, dbfs / 20)
        let scale = rms > 0 ? target / rms : 0
        for i in s.indices {
            s[i] *= scale
        }
        return s
    }

    /// Pass-rate (0...1) when `frame` is fed `count` times through `gate` in a row.
    private func passRate(_ gate: inout NearFieldGate, frame: [Float], count: Int) -> Double {
        var passed = 0
        for _ in 0 ..< count where gate.shouldPass(frame: frame) {
            passed += 1
        }
        return Double(passed) / Double(count)
    }

    func testSilenceIsDropped() {
        var gate = NearFieldGate()
        XCTAssertFalse(gate.shouldPass(frame: [Float](repeating: 0, count: frameLen)))
    }

    func testLoudCloseVoicePasses() {
        var gate = NearFieldGate()
        // ~-13 dBFS voiced tone: a person speaking right into the mic.
        XCTAssertTrue(gate.shouldPass(frame: sine(freq: 150, amplitude: 0.3)))
    }

    func testQuietFarVoiceIsDropped() {
        var gate = NearFieldGate()
        // ~-47 dBFS voiced tone: a real voice, but across the room. Below floor + margin, so it never opens a turn.
        XCTAssertFalse(gate.shouldPass(frame: sine(freq: 150, amplitude: 0.006)))
    }

    func testLoudNonSpeechNoiseIsDropped() {
        var gate = NearFieldGate()
        // Loud but high-ZCR: wind / rattle / a clap. Beats the level check, fails voicedness, so it's silenced.
        XCTAssertFalse(gate.shouldPass(frame: alternating(amplitude: 0.3)))
    }

    func testHangoverKeepsWordTailOpen() {
        var gate = NearFieldGate(params: .init(hangoverFrames: 3))
        XCTAssertTrue(gate.shouldPass(frame: sine(freq: 150, amplitude: 0.3)))
        // A quiet trailing frame (word ending) must still pass while the hangover holds, then close.
        let quiet = sine(freq: 150, amplitude: 0.006)
        XCTAssertTrue(gate.shouldPass(frame: quiet))
        XCTAssertTrue(gate.shouldPass(frame: quiet))
        XCTAssertTrue(gate.shouldPass(frame: quiet))
        XCTAssertFalse(gate.shouldPass(frame: quiet))
    }

    func testFloorAdaptsSoNoiseRaisesTheBar() {
        // A mid-level voice (~-29 dBFS) passes in a quiet room...
        var quietRoom = NearFieldGate()
        XCTAssertTrue(quietRoom.shouldPass(frame: sine(freq: 150, amplitude: 0.05)))

        // ...but after the gate has tracked a loud noisy environment, the same mid-level voice is no longer "the close speaker" and is gated out — only a louder, closer voice gets through. This is the near-field principle adapting to context.
        var noisyStreet = NearFieldGate()
        for _ in 0 ..< 100 {
            _ = noisyStreet.shouldPass(frame: alternating(amplitude: 0.3))
        }
        XCTAssertFalse(noisyStreet.shouldPass(frame: sine(freq: 150, amplitude: 0.05)))
        // The user's own close, loud voice still gets through in that same noisy environment.
        XCTAssertTrue(noisyStreet.shouldPass(frame: sine(freq: 150, amplitude: 0.4)))
    }

    func testResetClearsAdaptedState() {
        var gate = NearFieldGate()
        for _ in 0 ..< 100 {
            _ = gate.shouldPass(frame: alternating(amplitude: 0.3))
        }
        gate.reset()
        // After reset the floor is back to baseline, so the mid-level voice passes again.
        XCTAssertTrue(gate.shouldPass(frame: sine(freq: 150, amplitude: 0.05)))
    }

    // MARK: - Preserve tests (the gate must NOT eat the user's real speech)

    func testNormalSpeechPreservedInQuietRoom() {
        var gate = NearFieldGate()
        // Normal speech ≈ -20 dBFS in a quiet room must pass essentially all the time.
        XCTAssertGreaterThan(passRate(&gate, frame: speechFrame(dbfs: -20), count: 50), 0.95)
    }

    func testSoftSpeechPreservedInQuietRoom() {
        var gate = NearFieldGate()
        // Soft speech ≈ -30 dBFS in a quiet room must still pass — the floor sits low, so the user doesn't have to be loud when it's quiet.
        XCTAssertGreaterThan(passRate(&gate, frame: speechFrame(dbfs: -30), count: 50), 0.9)
    }

    func testNormalSpeechSurvivesAfterLoudNoiseRaisedTheFloor() {
        // The real starvation risk Wes flagged: a loud noisy stretch climbs the floor, then the user speaks at a NORMAL level. If the gate now demands loud speech, it eats normal talk in any loud room. Normal -20 dBFS speech must still mostly get through.
        var gate = NearFieldGate()
        for _ in 0 ..< 100 {
            _ = gate.shouldPass(frame: alternating(amplitude: 0.3))
        }
        XCTAssertGreaterThan(passRate(&gate, frame: speechFrame(dbfs: -20), count: 50), 0.8)
    }
}
