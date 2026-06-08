import AVFoundation
import Foundation

/// Plays the bundled `Resources/VoiceSamples/<voice>.wav` previews used in the persona-create voice picker. Uses `AVAudioPlayer` directly — keeps the AVAudioEngine pipeline untouched, which is critical because the engine drives the live conversation and must not be disturbed by a 4-second preview tap.
///
/// `Bundle.main.url(forResource:withExtension:)` resolves WAVs that xcodegen has flagged as a resource folder (see project.yml).
@MainActor
@Observable
final class VoicePreviewPlayer {
    /// The voice id currently playing back, if any. Used by the UI to show a stop / playing affordance on one row at a time.
    private(set) var nowPlaying: String?

    @ObservationIgnored private var player: AVAudioPlayer?

    /// Voice ids that have a bundled preview wav. Voices missing here (ballad, cedar, marin, verse) show "preview unavailable".
    static let availableVoiceIds: Set<String> = ["alloy", "ash", "coral", "echo", "sage", "shimmer"]

    static func hasPreview(_ voiceId: String) -> Bool {
        availableVoiceIds.contains(voiceId.lowercased())
    }

    func play(voiceId: String) {
        let id = voiceId.lowercased()
        guard Self.hasPreview(id) else { return }
        guard let url = Bundle.main.url(forResource: id, withExtension: "wav") else {
            return
        }
        do {
            // Stop any in-flight playback first so taps on a different row don't overlap.
            player?.stop()
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
            nowPlaying = voiceId
            // Clear `nowPlaying` after the sample duration so the UI badge resets without needing a delegate.
            let duration = newPlayer.duration
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                guard let self else { return }
                if nowPlaying == voiceId {
                    nowPlaying = nil
                }
            }
        } catch {
            nowPlaying = nil
        }
    }

    func stop() {
        player?.stop()
        nowPlaying = nil
    }
}
