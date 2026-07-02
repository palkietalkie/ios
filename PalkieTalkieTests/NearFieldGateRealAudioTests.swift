@preconcurrency import AVFoundation
@testable import PalkieTalkie
import XCTest

/// Replays the user's REAL recorded scooter mic audio through the old fixed -45 dBFS gate and the new NearFieldGate, asserting on the actual signal rather than a synthetic proxy. The suppress/preserve mechanics are at the two assertions below.
///
/// Fixture `Fixtures/session_896058bc-d8d1-446c-846b-f2c56d34f0ed_mic.wav` (163.8s) is a scooter session of the founder riding alone, his voice only (no third party), safe to commit. The session_id in the filename traces it to the DB row. Bundled as a test resource so this runs in CI, not read from /tmp (a CI runner has no clip there, the test would silently no-op = fake coverage). Regenerate: `backend/scripts/neon/dump_session_audio.py 896058bc-d8d1-446c-846b-f2c56d34f0ed`.
///
/// Transcript ground truth (offsets are turn-flush times, so speech is the seconds just before): surround-noise garbage the AI reacted to at "什麼" ~t=15s; the user's real speech at t=31–34 ("No no, I'm riding my scooter") and t=44–48 ("...I didn't say that").
final class NearFieldGateRealAudioTests: XCTestCase {
    private let frameLen = 480 // 20ms @ 24kHz
    private let oldGateDbfs: Float = -45 // the fixed threshold the new gate replaced

    private func loadSamples(_ url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let fmt = file.processingFormat
        let count = AVAudioFrameCount(file.length)
        guard count > 0, let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: count),
              (try? file.read(into: buf)) != nil, let ch = buf.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(buf.frameLength)))
    }

    /// Per-second new-gate pass fractions + overall new/old pass% for the bundled clip.
    private func analyze() -> (newOverall: Int, oldOverall: Int, perSecondNew: [Double])? {
        guard let url = Bundle(for: type(of: self)).url(
            forResource: "session_896058bc-d8d1-446c-846b-f2c56d34f0ed_mic",
            withExtension: "wav",
        ),
            let samples = loadSamples(url) else { return nil }
        var gate = NearFieldGate()
        let fps = 24000 / frameLen // 50 frames/sec
        var sNew = 0, sTot = 0, tNew = 0, tOld = 0, tTot = 0
        var perSecondNew: [Double] = []
        var i = 0
        while i + frameLen <= samples.count {
            let frame = Array(samples[i ..< i + frameLen])
            let oldPass = AudioMath.rmsDbfs(frame) >= oldGateDbfs
            let newPass = gate.shouldPass(frame: frame)
            if newPass { sNew += 1; tNew += 1 }
            if oldPass { tOld += 1 }
            sTot += 1; tTot += 1
            if sTot == fps {
                perSecondNew.append(Double(sNew) / Double(sTot))
                sNew = 0; sTot = 0
            }
            i += frameLen
        }
        let nO = tTot > 0 ? Int(round(Double(tNew) / Double(tTot) * 100)) : 0
        let oO = tTot > 0 ? Int(round(Double(tOld) / Double(tTot) * 100)) : 0
        return (nO, oO, perSecondNew)
    }

    /// Mean new-gate pass fraction over an inclusive second range (clamped to what's available).
    private func windowMean(_ perSecond: [Double], _ range: ClosedRange<Int>) -> Double {
        let lo = max(0, range.lowerBound), hi = min(perSecond.count - 1, range.upperBound)
        guard lo <= hi else { return 0 }
        let slice = perSecond[lo ... hi]
        return slice.reduce(0, +) / Double(slice.count)
    }

    func testScooterClipSuppressesNoiseAndPreservesRealSpeech() {
        guard let r = analyze() else {
            XCTFail("bundled fixture session_896058bc-d8d1-446c-846b-f2c56d34f0ed_mic.wav not found in test bundle")
            return
        }
        print("REAL-AUDIO[scooter]: new \(r.newOverall)% pass vs old \(r.oldOverall)% pass")
        // Suppress: the new gate passes strictly LESS overall — that delta is the surround noise removed before the VAD can fire on it.
        XCTAssertLessThan(r.newOverall, r.oldOverall)
        // Preserve (real audio): at the transcript-confirmed speech windows the gate must keep most of the user's voice, not starve it.
        XCTAssertGreaterThan(windowMean(r.perSecondNew, 31 ... 34), 0.6)
        XCTAssertGreaterThan(windowMean(r.perSecondNew, 44 ... 48), 0.6)
    }
}
