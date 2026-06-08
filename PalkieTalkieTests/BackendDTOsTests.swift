@testable import PalkieTalkie
import XCTest

/// Snake-case wire-shape round-trip tests for the DTOs `BackendDTOs.swift` defines. The full per-endpoint coverage lives in `BackendEndpointsTests`; this file pairs the DTO source file so the CI test-pair check accepts the extraction.
final class BackendDTOsTests: XCTestCase {
    func testStartResponseRoundTripsThroughSnakeCaseJSON() throws {
        let original = StartResponse(
            sessionId: "srv-1",
            textPrompt: "be a friend",
            voiceId: "alloy",
            wsUrl: "wss://example.test",
            provider: "openai",
            ephemeralToken: "ek_test",
        )
        let data = try BackendAPI.encoder.encode(original)
        // Verify the wire format actually used snake_case (camelCase would crash the backend's pydantic parsing).
        let jsonString = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(jsonString.contains("session_id"))
        XCTAssertTrue(jsonString.contains("ws_url"))
        XCTAssertFalse(jsonString.contains("sessionId"))
        let decoded = try BackendAPI.decoder.decode(StartResponse.self, from: data)
        XCTAssertEqual(decoded.sessionId, "srv-1")
        XCTAssertEqual(decoded.provider, "openai")
    }

    func testSessionSummaryUsesSessionIdAsIdentifiable() {
        let summary = SessionSummary(
            sessionId: "abc",
            personaId: nil,
            startedAt: Date(),
            endedAt: nil,
            durationSeconds: nil,
        )
        XCTAssertEqual(summary.id, "abc", "Identifiable id must be sessionId so SwiftUI lists key by it")
    }

    func testBackendErrorErrorDescriptionsFormatHumanReadable() {
        XCTAssertEqual(BackendError.invalidURL.errorDescription, "Invalid backend URL")
        XCTAssertEqual(BackendError.notAuthenticated(reason: "no jwt").errorDescription, "Not signed in (no jwt)")
        XCTAssertEqual(BackendError.http(404, "missing").errorDescription, "HTTP 404: missing")
        XCTAssertEqual(BackendError.decoding("oops").errorDescription, "Couldn't decode response: oops")
    }
}
