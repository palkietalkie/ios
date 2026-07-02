@testable import PalkieTalkie
import XCTest

final class CrashStoreTests: XCTestCase {
    private func tempStore() -> CrashStore {
        CrashStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    private func sampleRecord() -> CrashRecord {
        CrashRecord(
            kind: "signal", name: "SIGABRT", reason: "fatal signal 6",
            topFrame: "Foo.bar (Foo.swift:1)", stack: ["a"], build: "28",
            crashedAt: Date(timeIntervalSince1970: 1_700_000_000),
        )
    }

    func testSaveThenLoadRoundTrips() {
        let store = tempStore()
        defer { store.clear() }
        let record = sampleRecord()
        store.save(record)
        XCTAssertEqual(store.load(), record)
    }

    func testLoadIsNilWhenNothingSaved() {
        XCTAssertNil(tempStore().load())
    }

    func testClearRemovesTheRecord() {
        let store = tempStore()
        store.save(sampleRecord())
        store.clear()
        XCTAssertNil(store.load())
    }
}
