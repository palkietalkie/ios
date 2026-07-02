@testable import PalkieTalkie
import XCTest

final class AudioUploadOutboxTests: XCTestCase {
    private func makeOutbox() -> AudioUploadOutbox {
        AudioUploadOutbox(
            dir: FileManager.default.temporaryDirectory
                .appendingPathComponent("outbox-test-\(UUID().uuidString)", isDirectory: true),
        )
    }

    private var scratch: [AudioUploadOutbox] = []
    override func tearDown() {
        for outbox in scratch {
            try? FileManager.default.removeItem(at: outbox.dir)
        }
        scratch.removeAll()
        super.tearDown()
    }

    func testEnqueuePersistsAndPendingRecoversSessionIdAndSource() throws {
        let outbox = makeOutbox()
        scratch.append(outbox)
        let sessionId = UUID().uuidString
        try outbox.enqueue(sessionId: sessionId, source: "mic", deflatedWav: Data([1, 2, 3]))

        let pending = outbox.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.sessionId, sessionId)
        XCTAssertEqual(pending.first?.source, "mic")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(pending.first).url), Data([1, 2, 3]))
    }

    func testFlushDeliversAndRemovesOnSuccess() async throws {
        let outbox = makeOutbox()
        scratch.append(outbox)
        try outbox.enqueue(sessionId: "s1", source: "mic", deflatedWav: Data([9]))
        try outbox.enqueue(sessionId: "s1", source: "model", deflatedWav: Data([8]))

        let delivered = await outbox.flush { _, _, _ in true }
        XCTAssertEqual(delivered, 2)
        XCTAssertEqual(outbox.pending().count, 0, "delivered payloads are removed")
    }

    func testFlushRetainsOnFailure() async throws {
        let outbox = makeOutbox()
        scratch.append(outbox)
        try outbox.enqueue(sessionId: "s1", source: "mic", deflatedWav: Data([9]))

        let delivered = await outbox.flush { _, _, _ in false }
        XCTAssertEqual(delivered, 0)
        XCTAssertEqual(outbox.pending().count, 1, "a failed upload stays queued for the next flush")
    }

    func testFlushDeliversOnlyTheSuccessfulTrackAndRetainsTheFailedOne() async throws {
        let outbox = makeOutbox()
        scratch.append(outbox)
        try outbox.enqueue(sessionId: "s1", source: "mic", deflatedWav: Data([9]))
        try outbox.enqueue(sessionId: "s1", source: "model", deflatedWav: Data([8]))

        // Only "model" succeeds; "mic" fails and must remain.
        _ = await outbox.flush { _, source, _ in source == "model" }
        let remaining = outbox.pending()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.source, "mic")
    }

    func testEnqueueOverwritesSameSessionAndSource() throws {
        let outbox = makeOutbox()
        scratch.append(outbox)
        try outbox.enqueue(sessionId: "s1", source: "mic", deflatedWav: Data([1]))
        try outbox.enqueue(sessionId: "s1", source: "mic", deflatedWav: Data([2, 2]))

        let pending = outbox.pending()
        XCTAssertEqual(pending.count, 1, "re-enqueuing the same track replaces, not duplicates")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(pending.first).url), Data([2, 2]))
    }

    func testPendingIgnoresUnparseableFilenames() throws {
        let outbox = makeOutbox()
        scratch.append(outbox)
        try FileManager.default.createDirectory(at: outbox.dir, withIntermediateDirectories: true)
        // A stray file without the "sessionId__source" shape must not surface as a pending upload.
        try Data([0]).write(to: outbox.dir.appendingPathComponent("garbage.txt"))
        try outbox.enqueue(sessionId: "s1", source: "mic", deflatedWav: Data([1]))

        XCTAssertEqual(outbox.pending().count, 1)
        XCTAssertEqual(outbox.pending().first?.source, "mic")
    }

    func testPendingIsEmptyWhenDirectoryMissing() {
        let outbox = makeOutbox()
        // Never created the directory; pending() must return [] rather than throw.
        XCTAssertEqual(outbox.pending().count, 0)
    }
}
