import SwiftUI

/// Talk-view center indicator: a row of state-colored bars that rise with the tutor's live voice and rest on a low flat line when quiet. Replaced the old mic glyph, which read as a tappable push-to-talk button (Ayumi feedback) — Talk is a two-way conversation and this is purely a readout: `color` = connection state, bar height = the tutor's real output amplitude (`level`, 0…1, from AudioStreamer via SessionController.aiOutputLevel). Not hit-testable, so taps fall through: it is not a button.
struct CenterIndicator: View {
    let color: Color
    var size: CGFloat = 80
    /// Read per frame inside the TimelineView so the bars track the live amplitude without the view needing to observe it.
    let level: () -> CGFloat

    static let barCount = 5

    /// Bar height fraction (0…1) for `index` given the current output `level` and animation time `t`. A low flat line at `level == 0`; as the tutor gets louder the bars grow, and a per-bar phase offset gives a non-uniform wave (never flat across all bars, never overflowing the frame). Pure and deterministic so the mapping is unit-testable without rendering.
    static func barAmplitude(level: CGFloat, index: Int, t: Double) -> CGFloat {
        let floor: CGFloat = 0.12
        let clamped = min(max(level, 0), 1)
        let phase = Double(index) * 0.7
        let shape = 0.55 + 0.45 * abs(sin(t * 5 + phase)) // 0.55…1.0 per-bar wave
        return floor + (1 - floor) * clamped * CGFloat(shape)
    }

    var body: some View {
        // Fixed 80×80 footprint (the old mic's size) so the captions-toggle position tests still hold; the glow overflows as a shadow without changing this frame.
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let lv = level()
            HStack(spacing: size * 0.06) {
                ForEach(0 ..< Self.barCount, id: \.self) { i in
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: size * 0.12, height: size * Self.barAmplitude(level: lv, index: i, t: t))
                }
            }
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.15 + 0.5 * Double(lv)), radius: 4 + 12 * Double(lv))
        }
        .allowsHitTesting(false)
    }
}
