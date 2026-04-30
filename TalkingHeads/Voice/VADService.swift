import AVFoundation
import Foundation
import RealTimeCutVADLibrary

// TERMINOLOGY:
// - `NSObject`: Base class for Objective-C compatible classes. Required here because
//   the VAD library's delegate protocol is Objective-C based.
//   Think of it as extending a base class to satisfy an interface requirement.
// - `delegate`: A design pattern where object A delegates work to object B.
//   Like the observer/callback pattern — B implements a protocol (interface),
//   A calls B's methods when events happen. Common in Apple APIs.
// - `extension VADService: VADWrapperDelegate`: Adds protocol conformance to the class.
//   Like `implements VADWrapperDelegate` in Java/TS, but written separately from the class.
// - `var onVoiceStarted: (() -> Void)?`: An optional closure (callback function).
//   `() -> Void` = a function that takes no args and returns nothing (like `() => void` in TS).

/// Wraps Silero v5 VAD to detect speech start/end from mic audio.
final class VADService: NSObject {
    private var vadWrapper: VADWrapper?

    var onVoiceStarted: (() -> Void)?
    var onVoiceEnded: ((Data) -> Void)?

    override init() {
        super.init()
        vadWrapper = VADWrapper()
        vadWrapper?.delegate = self
    }

    /// Feed 16kHz mono float32 audio from the mic tap.
    func process(_ buffer: AVAudioPCMBuffer) {
        vadWrapper?.processAudioBuffer(buffer)
    }

    func reset() {
        vadWrapper?.reset()
    }
}

extension VADService: VADWrapperDelegate {
    func voiceStartCallback() {
        onVoiceStarted?()
    }

    func voiceEndCallback(_ audioData: Data) {
        onVoiceEnded?(audioData)
    }
}
