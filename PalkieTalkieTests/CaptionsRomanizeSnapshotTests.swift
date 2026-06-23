@testable import PalkieTalkie
import SwiftUI
import XCTest

/// Renders the caption area in both states (original script vs romanized) with the ABC + CC toggle row, so the on/off interaction can be eyeballed without a live Japanese session. Writes to ios/snapshots/ (tracked). Not an assertion test, a visual aid.
@MainActor
final class CaptionsRomanizeSnapshotTests: XCTestCase {
    func testRenderOriginalAndRomaji() throws {
        let snapshotsDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("snapshots")
        try FileManager.default.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)

        let transcript = [
            TranscriptChunk(speaker: .persona, text: "今日はいい天気ですね。散歩でもどうですか。"),
            TranscriptChunk(speaker: .user, text: "そうですね、行きましょう。"),
        ]

        for (kind, romanized) in [("original", false), ("romaji", true)] {
            let view = VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Spacer()
                    CaptionsRomanizeToggle(romanized: .constant(romanized))
                    CaptionsToggle(enabled: .constant(true))
                }
                .padding()
                // CaptionsScroll wraps a ScrollView, which ImageRenderer can't capture; render the same merged lines in a static stack so the snapshot shows the text.
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(mergedCaptions(transcript)) { line in
                        Text(romanized ? romanize(line.text) : line.text)
                            .font(.body)
                            .foregroundStyle(line.speaker == .user ? .blue : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal)
                Spacer()
            }
            .frame(width: 393, height: 420)
            .background(Color(.systemBackground))
            .environment(\.colorScheme, .dark)
            .tint(Color.brandCoral)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage, "ImageRenderer produced no image")
            let png = try XCTUnwrap(image.pngData())
            try png.write(to: snapshotsDir.appendingPathComponent("captions-\(kind).png"))
            print("WROTE captions-\(kind).png")
        }
    }
}
