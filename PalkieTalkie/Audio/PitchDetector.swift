import Foundation

/// YIN-style fundamental-frequency estimator. Run on each mic buffer to get one F0 sample (or nil for unvoiced
/// / silent frames). Pitch range across a session = max F0 minus min F0 across detected frames.
///
/// Limited to 70-500 Hz — the range that covers natural human speech. Outside this we return nil so the
/// stat doesn't get blown out by clipping artifacts, whistles, or DC drift.
enum PitchDetector {
    static let minHz: Float = 70
    static let maxHz: Float = 500
    private static let threshold: Float = 0.15
    private static let silenceEnergyFloor: Float = 0.01

    static func detect(samples: [Float], sampleRate: Float) -> Float? {
        let n = samples.count
        guard n > 0, sampleRate > 0 else { return nil }

        // Energy gate — skip silence and noise frames so they don't pollute the pitch range.
        var energy: Float = 0
        for s in samples {
            energy += abs(s)
        }
        energy /= Float(n)
        guard energy >= silenceEnergyFloor else { return nil }

        let minTau = Int(sampleRate / maxHz)
        let maxTau = min(Int(sampleRate / minHz), n / 2 - 1)
        guard minTau >= 1, maxTau > minTau else { return nil }

        // Step 1: squared-difference autocorrelation. O(n * maxTau).
        var d = [Float](repeating: 0, count: maxTau + 1)
        let usableLength = n - maxTau
        for tau in 1 ... maxTau {
            var sum: Float = 0
            var j = 0
            while j < usableLength {
                let diff = samples[j] - samples[j + tau]
                sum += diff * diff
                j += 1
            }
            d[tau] = sum
        }

        // Step 2: cumulative mean normalized difference.
        var dPrime = [Float](repeating: 1, count: maxTau + 1)
        var runningSum: Float = 0
        for tau in 1 ... maxTau {
            runningSum += d[tau]
            if runningSum > 0 {
                dPrime[tau] = d[tau] * Float(tau) / runningSum
            }
        }

        // Step 3: first tau in [minTau, maxTau] where dPrime < threshold, then walk down to its local min.
        var tau = minTau
        while tau < maxTau {
            if dPrime[tau] < threshold {
                while tau + 1 < maxTau, dPrime[tau + 1] < dPrime[tau] {
                    tau += 1
                }
                let pitch = sampleRate / Float(tau)
                return (pitch >= minHz && pitch <= maxHz) ? pitch : nil
            }
            tau += 1
        }
        return nil
    }
}

/// Tracks min/max F0 across a session. Thread-safe via actor.
actor PitchTracker {
    private var minHz: Float = .infinity
    private var maxHz: Float = -.infinity

    func ingest(samples: [Float], sampleRate: Float) {
        guard let pitch = PitchDetector.detect(samples: samples, sampleRate: sampleRate) else { return }
        if pitch < minHz { minHz = pitch }
        if pitch > maxHz { maxHz = pitch }
    }

    func range() -> (min: Float, max: Float)? {
        guard maxHz > -.infinity, minHz < .infinity, maxHz >= minHz else { return nil }
        return (minHz, maxHz)
    }

    func reset() {
        minHz = .infinity
        maxHz = -.infinity
    }
}
