import SwiftUI

// Live transcript renderer for the Talk screen, plus the CC toggle that shows/hides it.
//
// Single responsibility: present TranscriptChunks as readable flowing lines and let the user toggle captions on/off.
// Speaker turn changes start a new line; consecutive same-speaker subword tokens (the model emits "uh", "he", "y", ...) get concatenated so the user doesn't see one row per token. No "AI" / "You" labels — speaker is visually obvious from voice context.

/// Single rendered caption line — one speaker turn after consecutive-token concatenation.
struct CaptionLine: Identifiable {
    let id: UUID
    let speaker: TranscriptChunk.Speaker
    let text: String
}

/// Pure function: collapse consecutive same-speaker TranscriptChunks into rendered lines.
func mergedCaptions(_ chunks: [TranscriptChunk]) -> [CaptionLine] {
    var lines: [CaptionLine] = []
    for chunk in chunks {
        if var last = lines.last, last.speaker == chunk.speaker {
            last = CaptionLine(id: last.id, speaker: last.speaker, text: last.text + chunk.text)
            lines[lines.count - 1] = last
        } else {
            lines.append(CaptionLine(id: chunk.id, speaker: chunk.speaker, text: chunk.text))
        }
    }
    return lines
}

/// CC button, YouTube-style. The `captions.bubble` SF Symbol is just a speech bubble — users don't read it as captions, so render literal "CC" letters instead. Monochrome only (never a brand color): enabled is a brighter "CC" inside a filled pill; disabled is a dim "CC" with no fill. No underline. `.buttonStyle(.plain)` stops the toolbar from tinting the label blue. Styling is exposed as pure functions so the visual contract is unit-testable.
struct CaptionsToggle: View {
    @Binding var enabled: Bool

    /// Pill fill: a monochrome box when enabled, nothing when disabled. Never a brand color.
    static func fill(enabled: Bool) -> Color {
        enabled ? Color.primary.opacity(0.15) : .clear
    }

    /// "CC" letters: full brightness when enabled, dimmed when disabled.
    static func foreground(enabled: Bool) -> Color {
        enabled ? .primary : .secondary
    }

    var body: some View {
        Button {
            enabled.toggle()
        } label: {
            Text("CC")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .tracking(0.5)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundStyle(Self.foreground(enabled: enabled))
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Self.fill(enabled: enabled)),
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(enabled ? "Hide captions" : "Show captions")
    }
}

/// Scrolling transcript area. Auto-scrolls to the latest line when new chunks arrive.
struct CaptionsScroll: View {
    let transcript: [TranscriptChunk]

    var body: some View {
        let merged = mergedCaptions(transcript)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(merged) { line in
                        Text(line.text)
                            .font(.body)
                            .foregroundStyle(line.speaker == .user ? .blue : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .padding(.vertical, 8)
            }
            // Fill whatever vertical space ConversationView gives the captions block (it grants this view layout priority) rather than capping at a fixed 220pt that left the caption area cramped under the mic.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: merged.count) { _, _ in
                if let last = merged.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: merged.last?.text) { _, _ in
                if let last = merged.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
}
