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
    private let threshold = EmotionDetector.confidenceThreshold

    func testLabelAboveThresholdIsPresent() {
        XCTAssertEqual(
            EmotionDetector.presentCategories(in: [("laughter", 0.9)], threshold: threshold),
            [.laugh],
        )
    }

    func testLabelBelowThresholdIsIgnored() {
        XCTAssertTrue(
            EmotionDetector.presentCategories(in: [("laughter", 0.2)], threshold: threshold).isEmpty,
        )
    }

    func testNonEmotionalTopLabelDoesNotMaskAnEmotionalOne() {
        // "speech" outranks the laugh but maps to no category; the laugh still registers.
        XCTAssertEqual(
            EmotionDetector.presentCategories(
                in: [("speech", 0.95), ("laughter", 0.6)], threshold: threshold,
            ),
            [.laugh],
        )
    }

    func testEveryClearingCategoryIsPresentTogether() {
        XCTAssertEqual(
            EmotionDetector.presentCategories(
                in: [("giggling", 0.7), ("sigh", 0.8), ("typing", 0.99)], threshold: threshold,
            ),
            [.laugh, .sigh],
        )
    }

    func testNegativeCategoryRegisters() {
        XCTAssertEqual(
            EmotionDetector.presentCategories(in: [("groaning", 0.6)], threshold: threshold),
            [.groan],
        )
    }

    func testEmptyInputIsEmpty() {
        XCTAssertTrue(EmotionDetector.presentCategories(in: [], threshold: threshold).isEmpty)
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
