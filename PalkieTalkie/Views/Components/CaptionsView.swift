import SwiftUI

// Live transcript renderer for the Talk screen, plus the CC toggle that shows/hides it.
//
// Single responsibility: present TranscriptChunks as readable flowing lines and let the user toggle captions on/off.
// Speaker turn changes start a new line; consecutive same-speaker subword tokens (the model emits "uh", "he", "y", ...)
// get concatenated so the user doesn't see one row per token. No "AI" / "You" labels — speaker is visually obvious from
// voice context.

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

/// CC button. `captions.bubble` SF Symbol already contains "CC" in its glyph — no separate text label.
struct CaptionsToggle: View {
    @Binding var enabled: Bool

    var body: some View {
        Button {
            enabled.toggle()
        } label: {
            Image(systemName: enabled ? "captions.bubble.fill" : "captions.bubble")
                .font(.system(size: 22))
                .foregroundStyle(enabled ? .blue : .secondary)
                .padding(.vertical, 4)
        }
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
            .frame(maxHeight: 220)
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
