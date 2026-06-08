@testable import PalkieTalkie
import SwiftUI
import XCTest

/// Captions UI is the on-screen live transcript. The pure function `mergedCaptions` collapses sub-word stream tokens
/// from the realtime model into one line per speaker turn — without that, the user sees one row per "uh"/"he"/"y"
/// fragment.
@MainActor
final class CaptionsViewTests: XCTestCase {
    func testEmptyTranscriptYieldsNoLines() {
        XCTAssertEqual(mergedCaptions([]).count, 0)
    }

    func testSameSpeakerFragmentsConcat() {
        let chunks: [TranscriptChunk] = [
            .init(speaker: .persona, text: "He"),
            .init(speaker: .persona, text: "llo "),
            .init(speaker: .persona, text: "Wes"),
        ]
        let lines = mergedCaptions(chunks)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.text, "Hello Wes")
        XCTAssertEqual(lines.first?.speaker, .persona)
    }

    func testSpeakerSwitchStartsNewLine() {
        let chunks: [TranscriptChunk] = [
            .init(speaker: .persona, text: "Hi"),
            .init(speaker: .user, text: "Hey"),
            .init(speaker: .user, text: " back"),
        ]
        let lines = mergedCaptions(chunks)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].speaker, .persona)
        XCTAssertEqual(lines[0].text, "Hi")
        XCTAssertEqual(lines[1].speaker, .user)
        XCTAssertEqual(lines[1].text, "Hey back")
    }

    func testCaptionsToggleViewBodyEvaluates() {
        @State var enabled = false
        let view = CaptionsToggle(enabled: $enabled)
        // Touch .body so SwiftUI evaluates the ViewBuilder closures. Doesn't render to a window — we're only after code
        // coverage of the view-tree construction.
        _ = view.body
    }

    func testCaptionsScrollBodyEvaluates() {
        let view = CaptionsScroll(transcript: [
            .init(speaker: .user, text: "Hey"),
            .init(speaker: .persona, text: "Hi there"),
        ])
        _ = view.body
    }
}
