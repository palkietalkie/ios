@testable import PalkieTalkie
import XCTest

/// Holds a value across the @Sendable post closure (which can't mutate captured locals) so the test can assert what was delivered.
private final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) {
        stored = value
    }

    func get() -> T {
        lock.lock(); defer { lock.unlock() }; return stored
    }

    func set(_ value: T) {
        lock.lock(); defer { lock.unlock() }; stored = value
    }
}

/// Covers the report-on-next-launch behavior (the testable half). The crash-time capture (NSSetUncaughtExceptionHandler + signal handlers) needs a real process abort to fire, so it can't run in a unit test, that thin shell stays uncovered by design.
final class CrashReporterTests: XCTestCase {
    private func tempStore() -> CrashStore {
        CrashStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    private func sampleRecord() -> CrashRecord {
        CrashRecord(
            kind: "nsexception", name: "NSGenericException", reason: "boom",
            topFrame: "Foo.bar (Foo.swift:1)", stack: ["a"], build: "28",
            crashedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
    }

    func testReportsPendingCrashAndClearsOnSuccess() async {
        let store = tempStore()
        store.save(sampleRecord())
        let posted = Locked<CrashRecord?>(nil)
        let reported = await CrashReporter.reportPending(store: store) { record in
            posted.set(record)
            return true
        }
        XCTAssertTrue(reported)
        XCTAssertEqual(posted.get(), sampleRecord())
        XCTAssertNil(store.load(), "a delivered crash must be cleared so it isn't re-sent")
    }

    func testKeepsRecordWhenDeliveryFails() async {
        let store = tempStore()
        defer { store.clear() }
        store.save(sampleRecord())
        let reported = await CrashReporter.reportPending(store: store) { _ in false }
        XCTAssertFalse(reported)
        XCTAssertEqual(store.load(), sampleRecord(), "a failed send must keep the crash to retry next launch")
    }

    func testNoOpWhenNoPendingCrash() async {
        let store = tempStore()
        let called = Locked(false)
        let reported = await CrashReporter.reportPending(store: store) { _ in
            called.set(true)
            return true
        }
        XCTAssertFalse(reported)
        XCTAssertFalse(called.get())
    }
}
