import AVFoundation
import os
import OSLog
import SoundAnalysis

private let logger = Logger(subsystem: "com.palkietalkie", category: "emotion")

/// The emotion categories that move Affinity. Positives are favorability you earned; negatives are a penalty (the tutor got bored or let down). iOS only detects and counts categories, the backend owns each one's weight and sign, so the formula stays tunable server-side.
enum AffinityEmotion: String, CaseIterable {
    // Positive: raise affinity.
    case laugh
    case cheer
    case gasp
    // Negative: a penalty. A real partner sighs or groans when a thread dies, not just laughs, and that should cost you.
    case sigh
    case groan

    /// Map an Apple SoundAnalysis label to a category, or nil if it isn't an affinity signal. Substring match on the stem so it survives Apple relabeling the version1 set ("belly_laugh", "chuckle_chortle", ...).
    static func category(for identifier: String) -> AffinityEmotion? {
        let id = identifier.lowercased()
        if id.contains("laugh") || id.contains("giggl") || id.contains("chuckl")
            || id.contains("chortle") || id.contains("snicker") { return .laugh }
        if id.contains("cheer") || id.contains("applau") || id.contains("whoop") { return .cheer }
        if id.contains("gasp") { return .gasp }
        if id.contains("sigh") { return .sigh }
        if id.contains("groan") || id.contains("moan") || id.contains("whimper") { return .groan }
        return nil
    }
}

/// Per-category rising-edge counts. One event for a category = one transition from "absent" to "present" across the classifier windows, so a laugh spanning several windows is one event, not one per window. Each category edges independently.
struct AffinityCounters {
    private var counts: [AffinityEmotion: Int] = [:]
    private var active: Set<AffinityEmotion> = []

    mutating func observe(present: Set<AffinityEmotion>) {
        for category in present.subtracting(active) {
            counts[category, default: 0] += 1
        }
        active = present
    }

    func count(_ category: AffinityEmotion) -> Int {
        counts[category] ?? 0
    }
}

/// Live, on-device measurement of the tutor's emotional reactions, the raw material of the Affinity stat, taken straight off its output audio while it plays. This has to run during the conversation: once the session ends there is only transcript text, and emotion never lived in the text.
///
/// `@unchecked Sendable` is required, not a shortcut: `SNResultsObserving` mandates an `NSObject` subclass, and `NSObject` is not `Sendable`. Every non-`Sendable` member (the analyzer, the format, the frame cursor) is touched only on the private serial `queue`; the only cross-thread read, the counts, goes through an `OSAllocatedUnfairLock`. So the type is genuinely safe to hand to the `AudioStreamer` actor.
final class EmotionDetector: NSObject, SNResultsObserving, @unchecked Sendable {
    /// A label has to clear this to count. High enough that the classifier's constant low-confidence guesses ("speech" is almost always top) never trip a false reaction.
    static let confidenceThreshold = 0.45

    private let analyzer: SNAudioStreamAnalyzer
    private let format: AVAudioFormat
    private let queue = DispatchQueue(label: "com.palkietalkie.emotion")
    /// Touched only on `queue`. SoundAnalysis wants monotonically increasing frame positions across the stream.
    private var framePosition: AVAudioFramePosition = 0
    private let state = OSAllocatedUnfairLock(initialState: AffinityCounters())

    init?(format: AVAudioFormat) {
        self.format = format
        analyzer = SNAudioStreamAnalyzer(format: format)
        super.init()
        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            try analyzer.add(request, withObserver: self)
        } catch {
            logger.error("emotion classifier init failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Feed one chunk of the tutor's output audio. Takes `[Float]` (Sendable) rather than the source `AVAudioPCMBuffer` so nothing non-Sendable crosses onto the analysis queue; the buffer is rebuilt on the other side from the fixed output format.
    func analyze(samples: [Float]) {
        guard !samples.isEmpty else { return }
        queue.async { [self] in
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count),
            ) else { return }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { src in
                if let base = src.baseAddress {
                    buffer.floatChannelData?[0].update(from: base, count: samples.count)
                }
            }
            analyzer.analyze(buffer, atAudioFramePosition: framePosition)
            framePosition += AVAudioFramePosition(samples.count)
        }
    }

    /// Per-category event counts for the session, keyed by `AffinityEmotion.rawValue` ("laugh" / "cheer" / "gasp"). The backend owns the weights that combine these into the Affinity score.
    func counts() -> [String: Int] {
        state.withLock { counters in
            var out: [String: Int] = [:]
            for category in AffinityEmotion.allCases {
                out[category.rawValue] = counters.count(category)
            }
            return out
        }
    }

    /// Which affinity categories a classifier window puts "present": labels that map to a category AND clear the confidence threshold. Scans every prediction, not just the top one ("speech" usually outranks a laugh, but the laugh still clears the bar and is the signal we want). Pure and static so the core observer decision is unit-testable without a live SNClassificationResult, which the simulator can't produce.
    static func presentCategories(
        in predictions: [(identifier: String, confidence: Double)],
        threshold: Double,
    ) -> Set<AffinityEmotion> {
        Set(
            predictions
                .filter { $0.confidence >= threshold }
                .compactMap { AffinityEmotion.category(for: $0.identifier) },
        )
    }

    func request(_: SNRequest, didProduce result: SNResult) {
        guard let classification = result as? SNClassificationResult else { return }
        let present = Self.presentCategories(
            in: classification.classifications.map { ($0.identifier, $0.confidence) },
            threshold: Self.confidenceThreshold,
        )
        state.withLock { $0.observe(present: present) }
    }

    func request(_: SNRequest, didFailWithError error: Error) {
        logger.error("emotion analysis failed: \(String(describing: error), privacy: .public)")
    }
}
