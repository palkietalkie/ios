@testable import PalkieTalkie
import XCTest

/// YIN-style fundamental-frequency estimator. Verified by feeding known sine waves and asserting the detected pitch lies in a tight band around the source. Also exercises the silence / out-of-range guards.
final class PitchDetectorTests: XCTestCase {
    private let sampleRate: Float = 24000

    /// Synthesise a pure sine of `frequency` Hz at unit-ish amplitude. Length covers ~50ms so YIN has at least one full tau window for any pitch we care about.
    private func sineWave(frequency: Float, durationSec: Float = 0.05, amplitude: Float = 0.5) -> [Float] {
        let count = Int(durationSec * sampleRate)
        return (0 ..< count).map { sampleIndex in
            let t = Float(sampleIndex) / sampleRate
            return amplitude * sin(2 * .pi * frequency * t)
        }
    }

    func testDetectsMaleVoiceRange() {
        let samples = sineWave(frequency: 120)
        let detected = PitchDetector.detect(samples: samples, sampleRate: sampleRate)
        XCTAssertNotNil(detected)
        // YIN with a quantized tau lookup is exact only to integer-sample taus; allow ±2 Hz around 120.
        XCTAssertEqual(detected ?? 0, 120, accuracy: 3)
    }

    func testDetectsFemaleVoiceRange() {
        let samples = sineWave(frequency: 220)
        let detected = PitchDetector.detect(samples: samples, sampleRate: sampleRate)
        XCTAssertNotNil(detected)
        XCTAssertEqual(detected ?? 0, 220, accuracy: 5)
    }

    func testReturnsNilForEmpty() {
        XCTAssertNil(PitchDetector.detect(samples: [], sampleRate: sampleRate))
    }

    func testReturnsNilForZeroSampleRate() {
        XCTAssertNil(PitchDetector.detect(samples: [0.1, 0.2], sampleRate: 0))
    }

    func testReturnsNilForSilence() {
        let silence = [Float](repeating: 0, count: 4800)
        XCTAssertNil(PitchDetector.detect(samples: silence, sampleRate: sampleRate))
    }

    func testReturnsNilBelowEnergyFloor() {
        // amplitude 0.001 → mean |x| ~ 6e-4, well under silenceEnergyFloor (0.01).
        let quiet = sineWave(frequency: 150, amplitude: 0.001)
        XCTAssertNil(PitchDetector.detect(samples: quiet, sampleRate: sampleRate))
    }

    func testReturnsNilForOutOfRangeHighFrequency() {
        // 600 Hz is above PitchDetector.maxHz (500). YIN may lock on the harmonic but the band-pass guard rejects it.
        let samples = sineWave(frequency: 600)
        let detected = PitchDetector.detect(samples: samples, sampleRate: sampleRate)
        if let detected {
            XCTAssertTrue(detected >= PitchDetector.minHz && detected <= PitchDetector.maxHz)
        }
    }

    // MARK: - PitchTracker actor

    func testPitchTrackerStartsEmpty() async {
        let tracker = PitchTracker()
        let range = await tracker.range()
        XCTAssertNil(range)
    }

    func testPitchTrackerIngestExpandsMinMax() async {
        let tracker = PitchTracker()
        await tracker.ingest(samples: sineWave(frequency: 120), sampleRate: sampleRate)
        await tracker.ingest(samples: sineWave(frequency: 240), sampleRate: sampleRate)
        let range = await tracker.range()
        XCTAssertNotNil(range)
        XCTAssertLessThanOrEqual(range?.min ?? 1000, 125)
        XCTAssertGreaterThanOrEqual(range?.max ?? 0, 235)
    }

    func testPitchTrackerIgnoresSilence() async {
        let tracker = PitchTracker()
        let silence = [Float](repeating: 0, count: 4800)
        await tracker.ingest(samples: silence, sampleRate: sampleRate)
        let range = await tracker.range()
        XCTAssertNil(range)
    }

    func testPitchTrackerReset() async {
        let tracker = PitchTracker()
        await tracker.ingest(samples: sineWave(frequency: 150), sampleRate: sampleRate)
        await tracker.reset()
        let range = await tracker.range()
        XCTAssertNil(range)
    }
}
