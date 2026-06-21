import AVFoundation
@testable import PalkieTalkie
import XCTest

final class EmotionDetectorRuntimeTests: XCTestCase {
    private func outputFormat() -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false)!
    }

    func testFreshDetectorReportsZeroCounts() throws {
        guard let detector = EmotionDetector(format: outputFormat()) else {
            throw XCTSkip("on-device sound classifier unavailable in this environment")
        }
        let counts = detector.counts()
        for category in AffinityEmotion.allCases {
            XCTAssertEqual(counts[category.rawValue], 0)
        }
    }

    func testSilenceProducesNoEmotion() async throws {
        guard let detector = EmotionDetector(format: outputFormat()) else {
            throw XCTSkip("on-device sound classifier unavailable in this environment")
        }
        // One second of silence: exercises analyze() + the classifier callback, which must not register any reaction.
        detector.analyze(samples: [Float](repeating: 0, count: 24000))
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(detector.counts().values.reduce(0, +), 0)
    }
}

final class AffinityEmotionTests: XCTestCase {
    func testLaughVariantsMapToLaugh() {
        for label in ["laughter", "baby_laughter", "belly_laugh", "giggling", "chuckle_chortle", "snicker"] {
            XCTAssertEqual(AffinityEmotion.category(for: label), .laugh, "\(label)")
        }
    }

    func testCheerAndGaspMap() {
        XCTAssertEqual(AffinityEmotion.category(for: "cheering"), .cheer)
        XCTAssertEqual(AffinityEmotion.category(for: "applause"), .cheer)
        XCTAssertEqual(AffinityEmotion.category(for: "gasp"), .gasp)
    }

    func testNegativeSoundsMapToPenaltyCategories() {
        // Negatives are NOT dropped, they are penalty categories the backend subtracts.
        XCTAssertEqual(AffinityEmotion.category(for: "sigh"), .sigh)
        XCTAssertEqual(AffinityEmotion.category(for: "groaning"), .groan)
        XCTAssertEqual(AffinityEmotion.category(for: "moaning"), .groan)
        XCTAssertEqual(AffinityEmotion.category(for: "whimper"), .groan)
    }

    func testNonEmotionalSoundsAreNil() {
        for label in ["speech", "typing", "music", "silence", "crying_sobbing"] {
            XCTAssertNil(AffinityEmotion.category(for: label), "\(label)")
        }
    }
}

final class AffinityCountersTests: XCTestCase {
    func testEachCategoryEdgesIndependently() {
        var c = AffinityCounters()
        // A laugh that spans two windows, then a cheer, then both together.
        c.observe(present: [.laugh])
        c.observe(present: [.laugh]) // still laughing: no new laugh event
        c.observe(present: []) // reset
        c.observe(present: [.cheer])
        c.observe(present: [.laugh, .cheer]) // laugh edges again; cheer still active, no new cheer
        XCTAssertEqual(c.count(.laugh), 2)
        XCTAssertEqual(c.count(.cheer), 1)
        XCTAssertEqual(c.count(.gasp), 0)
    }

    func testSilentSessionCountsZero() {
        var c = AffinityCounters()
        c.observe(present: [])
        c.observe(present: [])
        XCTAssertEqual(c.count(.laugh), 0)
        XCTAssertEqual(c.count(.cheer), 0)
        XCTAssertEqual(c.count(.gasp), 0)
    }
}

final class EmotionPresentCategoriesTests: XCTestCase {
    private let reward = EmotionDetector.rewardConfidenceThreshold
    private let penalty = EmotionDetector.penaltyConfidenceThreshold

    private func present(_ p: [(String, Double)]) -> Set<AffinityEmotion> {
        EmotionDetector.presentCategories(in: p, rewardThreshold: reward, penaltyThreshold: penalty)
    }

    func testLabelAboveThresholdIsPresent() {
        XCTAssertEqual(present([("laughter", 0.9)]), [.laugh])
    }

    func testLabelBelowThresholdIsIgnored() {
        XCTAssertTrue(present([("laughter", 0.2)]).isEmpty)
    }

    func testNonEmotionalTopLabelDoesNotMaskAnEmotionalOne() {
        // "speech" outranks the laugh but maps to no category; the laugh still registers.
        XCTAssertEqual(present([("speech", 0.95), ("laughter", 0.6)]), [.laugh])
    }

    func testEveryClearingCategoryIsPresentTogether() {
        // sigh at 0.85 clears the higher penalty bar; giggling at 0.7 clears the reward bar.
        XCTAssertEqual(present([("giggling", 0.7), ("sigh", 0.85), ("typing", 0.99)]), [.laugh, .sigh])
    }

    func testLowConfidenceNegativeIsIgnored() {
        // The fix: a 0.6 "groan"/"sigh" cleared the old single 0.45 bar and falsely penalized. Now penalties need the higher bar, so this is dropped.
        XCTAssertTrue(present([("groaning", 0.6)]).isEmpty)
        XCTAssertTrue(present([("sigh", 0.6)]).isEmpty)
    }

    func testHighConfidenceNegativeRegisters() {
        XCTAssertEqual(present([("groaning", 0.85)]), [.groan])
    }

    func testRewardAndPenaltyAtSameConfidenceTreatedAsymmetrically() {
        // At 0.6, the reward counts but the penalty does not — the whole point of the split bar.
        XCTAssertEqual(present([("laughter", 0.6), ("sigh", 0.6)]), [.laugh])
    }

    func testEmptyInputIsEmpty() {
        XCTAssertTrue(present([]).isEmpty)
    }
}

final class AffinityCounterEdgeTests: XCTestCase {
    func testNegativeCategoriesEdgeIndependently() {
        var c = AffinityCounters()
        c.observe(present: [.sigh])
        c.observe(present: [.sigh, .groan])
        c.observe(present: [])
        c.observe(present: [.groan])
        XCTAssertEqual(c.count(.sigh), 1)
        XCTAssertEqual(c.count(.groan), 2)
    }

    func testSimultaneousCategoriesEachCountOnce() {
        var c = AffinityCounters()
        c.observe(present: [.laugh, .cheer, .gasp])
        XCTAssertEqual(c.count(.laugh), 1)
        XCTAssertEqual(c.count(.cheer), 1)
        XCTAssertEqual(c.count(.gasp), 1)
    }

    func testReEdgesAfterAGap() {
        var c = AffinityCounters()
        c.observe(present: [.laugh])
        c.observe(present: [])
        c.observe(present: [.laugh])
        c.observe(present: [])
        c.observe(present: [.laugh])
        XCTAssertEqual(c.count(.laugh), 3)
    }
}
