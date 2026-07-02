import Foundation

/// Format a tutor-speed playback multiplier for display next to the level label ("Slow · 0.85×"), so the user sees the concrete rate and "slow" vs "very slow" stops being ambiguous. `%g` drops trailing zeros: 0.7 → "0.7×", 1.0 → "1×", 1.15 → "1.15×". The number comes from the backend (the same audio.output.speed the audio actually uses); this only renders it. Pure value, so it's shown with Text(verbatim:), not localized.
func formatSpeedRate(_ rate: Double) -> String {
    String(format: "%g×", rate)
}
