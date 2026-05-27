import AVFoundation
import Foundation

enum AudioSessionError: Error {
    case microphonePermissionDenied
    case configurationFailed(Error)
}

/// AVAudioSession is a process-wide singleton; this is a thin async wrapper so callers don't have to think about
/// completion handlers or main-thread isolation.
enum AudioSessionManager {
    static func configureForFullDuplexVoice() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                // `.default` mode (NOT `.videoChat` / `.voiceChat`) — those modes enable iOS's voice processing AGC +
                // noise gate at the session level, which silences sub-`-11 dBFS` audio as "background noise". OpenAI
                // Realtime sends quieter TTS than PersonaPlex Opus, so the gate killed playback entirely. We still need
                // AEC (so the AI doesn't hear itself), but we enable it surgically on the mic input via
                // `inputNode.setVoiceProcessingEnabled(true)` in `AudioStreamer.start()` rather than session-wide.
                mode: .default,
                // `.allowBluetoothA2DP` (high-quality output) + `.allowBluetoothHFP` (hands-free mic + speaker) let
                // AirPods carry both directions. `.defaultToSpeaker` only kicks in when NOTHING is connected —
                // connecting AirPods automatically overrides to AirPods, just like other media apps. DO NOT add
                // `overrideOutputAudioPort(.speaker)` here; that forces the bottom speaker regardless of route and
                // breaks AirPods/headphones.
                options: [.allowBluetoothA2DP, .allowBluetoothHFP, .defaultToSpeaker, .duckOthers]
            )
            // 24kHz matches PersonaPlex / Mimi target; iOS will resample if hardware mismatches.
            try session.setPreferredSampleRate(24000)
            // 20ms buffers keep mic→server latency tight without over-fragmenting packets.
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw AudioSessionError.configurationFailed(error)
        }
    }

    static func requestMicrophonePermission() async throws {
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        if !granted {
            throw AudioSessionError.microphonePermissionDenied
        }
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
