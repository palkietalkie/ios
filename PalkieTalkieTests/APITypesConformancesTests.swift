@testable import PalkieTalkie
import XCTest

/// The generated wire structs are pure Codable; `APITypesConformances.swift` adds the SwiftUI list/picker conformances (Identifiable id-mapping, LanguageOut Hashable) and the iOS-name aliases. These pin that the id keys map to the natural field a list should key by, so a regression there (which would silently break ForEach diffing) is caught here.
final class APITypesConformancesTests: XCTestCase {
    func testIdentifiableIdsMapToNaturalKeys() {
        let summary = SessionSummary(
            sessionId: "sess-1", personaId: nil, personaName: nil,
            startedAt: Date(), endedAt: nil, durationSeconds: nil,
        )
        XCTAssertEqual(summary.id, "sess-1")

        let coverage = CefrCoverage(level: "B1", totalWords: 100, usedWords: 40, coveragePct: 0.4)
        XCTAssertEqual(coverage.id, "B1")

        let status = ProviderStatus(provider: "google", connected: true, expiresAt: nil)
        XCTAssertEqual(status.id, "google")
    }

    func testLanguageOutHashableAndIdentifiableKeyOnName() {
        let a = LanguageOut(name: "English", accents: ["us_general"])
        let b = LanguageOut(name: "English", accents: ["uk_rp"]) // different accents, same name
        let c = LanguageOut(name: "Japanese", accents: [])
        XCTAssertEqual(a.id, "English")
        // Identity is by name, so a == b despite differing accents — Picker selection keys by name.
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(Set([a, b, c]).count, 2)
    }

    /// The iOS-name aliases resolve to the generated types, so a value decoded as the generated type is usable through the alias name (and vice versa) — they are the same type, not a copy.
    func testAliasesAreTheGeneratedTypes() throws {
        let json = #"{"id":"m1","original":"i has","correction":"I have","count":3}"#
        let mistake: Mistake = try BackendAPI.decoder.decode(
            Mistake.self, from: XCTUnwrap(json.data(using: .utf8)),
        )
        let asGenerated: MistakeOut = mistake // compiles only if Mistake IS MistakeOut
        XCTAssertEqual(asGenerated.id, "m1")
        XCTAssertEqual(asGenerated.correction, "I have")
    }
}
