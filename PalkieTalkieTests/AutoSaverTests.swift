@testable import PalkieTalkie
import XCTest

@MainActor
final class AutoSaverTests: XCTestCase {
    func testNoOpWhenSnapshotUnchangedSinceMarkSaved() async throws {
        // The core guard that prevents the load → save loop: an unchanged snapshot must not save.
        let saver = AutoSaver<Int>()
        saver.markSaved(1)
        var saved = false
        saver.schedule(current: 1, loaded: true, debounce: .zero) { saved = true }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(saved)
    }

    func testSavesAfterAChange() async throws {
        let saver = AutoSaver<Int>()
        saver.markSaved(1)
        var saved = false
        saver.schedule(current: 2, loaded: true, debounce: .zero) { saved = true }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(saved)
    }

    func testNoOpWhenNotLoaded() async throws {
        // Before the first load there is nothing meaningful to persist — auto-save must stay quiet.
        let saver = AutoSaver<Int>()
        saver.markSaved(1)
        var saved = false
        saver.schedule(current: 2, loaded: false, debounce: .zero) { saved = true }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(saved)
    }

    func testRapidSchedulesCoalesceIntoOneSave() async throws {
        // A burst of keystrokes cancels the pending save each time, so only the last fires.
        let saver = AutoSaver<Int>()
        saver.markSaved(0)
        var count = 0
        for value in 1 ... 5 {
            saver.schedule(current: value, loaded: true, debounce: .milliseconds(100)) { count += 1 }
        }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(count, 1)
    }
}
