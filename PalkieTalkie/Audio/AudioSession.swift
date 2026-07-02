import AVFoundation
import Foundation

enum AudioSessionError: Error {
    case microphonePermissionDenied
    case configurationFailed(Error)
}

/// AVAudioSession is a process-wide singleton; this is a thin async wrapper so callers don't have to think about completion handlers or main-thread isolation.
enum AudioSessionManager {
    static func configureForFullDuplexVoice() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                // We request `.default` here, but note: AudioStreamer.start() calls `inputNode.setVoiceProcessingEnabled(true)` for AEC, and THAT forces the session's effective mode to `.voiceChat` at runtime regardless of what we set here (confirmed on-device: `sessionMode=AVAudioSessionModeVoiceChat`). So the mode choice does NOT keep us off the voice-processing path. What actually saves OpenAI's quieter TTS from iOS's noise gate (which silences sub-`-11 dBFS` audio and clipped "Wes"→"We") is disabling AGC via `isVoiceProcessingAGCEnabled = false` in AudioStreamer — the gate rides on AGC, AEC does not. Don't "fix" the runtime mode back to `.default`; that would disable the AEC we need and re-open the self-echo loop.
                mode: .default,
                // `.allowBluetoothA2DP` (high-quality output) + `.allowBluetoothHFP` (hands-free mic + speaker) let AirPods carry both directions. `.defaultToSpeaker` only kicks in when NOTHING is connected — connecting AirPods automatically overrides to AirPods, just like other media apps. DO NOT add `overrideOutputAudioPort(.speaker)` here; that forces the bottom speaker regardless of route and breaks AirPods/headphones.
                options: [.allowBluetoothA2DP, .allowBluetoothHFP, .defaultToSpeaker, .duckOthers],
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
