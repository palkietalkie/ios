import Foundation

/// Decides, per 20ms mic frame, whether the audio is the near-field primary speaker (the user, mouth close to the mic) versus far ambient or other voices, so only the user's own voice is ever streamed to the model. Everything that fails the gate is replaced with silence upstream, so the provider's server VAD never sees it and can't open a phantom turn off it.
///
/// Why this works without speaker enrollment: physics. The user's mouth is centimeters from the mic; everyone and everything else is across the room. Their voice arrives far louder than the background, so "much louder than the running ambient floor" is a strong proxy for "the person actually using the app." A loud near interferer standing right next to the user is the case this CANNOT separate — that needs true voiceprint matching (deferred), and humans struggle with it too.
///
/// Two checks, both must hold to count a frame as the user speaking:
///   1. Level over an ADAPTIVE floor. The floor tracks the background (rises on a noisy scooter, falls in a quiet office), so the same gate works in both: the user's close voice beats floor + margin in either place, while far voices and steady noise sit at or below the floor.
///   2. Voicedness. A loud non-speech transient (wind gust, scooter rattle, a clap) can momentarily beat the level check; its high zero-crossing rate gives it away as noise, not a voiced human utterance. The threshold is deliberately permissive so it only rejects obvious noise and never eats real speech.
/// A hangover keeps the gate open briefly after speech drops below threshold so word tails and short unvoiced consonants (s, f) at the end of an utterance aren't chopped.
struct NearFieldGate {
    struct Params {
        /// How far above the tracked ambient floor (dB) a frame must sit to count as the near speaker. Tuned with the preserve tests: at the floor cap (-30) this sets the bar at -22 dBFS, just below normal speech (-20), so normal talk survives even in a loud room (a higher margin starved normal speech at 0% pass — see testNormalSpeechSurvivesAfterLoudNoiseRaisedTheFloor). The cost is leaking more same-level noise; that's the unsolvable close-voice tradeoff (see hiring/OPEN_PROBLEMS.md #2).
        var marginDb: Float = 8
        /// Hard minimum level (dBFS). Below this it's room tone, never the user, regardless of how low the floor has drifted.
        var absoluteFloorDb: Float = -55
        /// Clamp on the tracked floor so it can neither sink so low that room tone passes nor rise so high that real speech can't beat floor + margin.
        var floorMinDb: Float = -60
        var floorMaxDb: Float = -30
        /// EMA rate the floor follows genuine non-speech frames toward the current ambient level. Slow so a brief loud sound doesn't inflate the floor and then deafen the gate to following speech.
        var floorAlpha: Float = 0.05
        /// Above this zero-crossing rate a loud frame is treated as noise, not voiced speech. Permissive on purpose: voiced speech sits well below this, so the guard only catches clear hiss/wind/rattle.
        var zcrMax: Float = 0.35
        /// Frames to keep passing after the last speech frame (12 * 20ms = 240ms), so trailing word endings survive.
        var hangoverFrames: Int = 12
    }

    private let params: Params
    private var floorDb: Float
    private var hangoverRemaining: Int = 0

    init(params: Params = Params()) {
        self.params = params
        floorDb = -50
    }

    /// Reset the adaptive state between sessions so a previous noisy environment doesn't bias the next session's floor.
    mutating func reset() {
        floorDb = -50
        hangoverRemaining = 0
    }

    /// True if this frame should be streamed to the model as-is; false if it should be silenced. Mutates the adaptive floor and hangover counter, so call exactly once per frame in order.
    mutating func shouldPass(frame: [Float]) -> Bool {
        let db = AudioMath.rmsDbfs(frame)
        let threshold = max(params.absoluteFloorDb, floorDb + params.marginDb)
        let loudEnough = db >= threshold
        let voiced = zeroCrossingRate(frame) <= params.zcrMax

        if loudEnough, voiced {
            // The user is speaking: open the gate and recharge the hangover. Don't adapt the floor toward speech, or the floor would chase the user's own voice up and start gating them out.
            hangoverRemaining = params.hangoverFrames
            return true
        }
        if hangoverRemaining > 0 {
            hangoverRemaining -= 1
            return true
        }
        // Genuine non-speech: let the floor follow the ambient level so the gate calibrates to wherever the user is.
        if db.isFinite {
            floorDb += params.floorAlpha * (db - floorDb)
            floorDb = min(max(floorDb, params.floorMinDb), params.floorMaxDb)
        }
        return false
    }

    /// Fraction of adjacent sample pairs that change sign. Low for voiced speech (energy concentrated at the pitch and low formants), high for broadband noise and unvoiced fricatives.
    private func zeroCrossingRate(_ frame: [Float]) -> Float {
        guard frame.count > 1 else { return 0 }
        var crossings = 0
        for i in 1 ..< frame.count where (frame[i] >= 0) != (frame[i - 1] >= 0) {
            crossings += 1
        }
        return Float(crossings) / Float(frame.count - 1)
    }
}
