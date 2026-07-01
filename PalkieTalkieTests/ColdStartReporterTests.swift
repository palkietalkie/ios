@testable import PalkieTalkie
import XCTest

/// In-memory backend that records the one `recordColdStart` call we expect.
private actor RecordingColdStartBackend: ConversationBackend {
    var coldStartCalls: [(durationMs: Int, timings: ColdStartTimings, sessionId: String)] = []

    func startConversation(personaId _: String, context _: ConversationContext,
                           topicOverride _: String?) async throws -> StartResponse
    {
        StartResponse(
            sessionId: "",
            textPrompt: "",
            voiceId: "",
            wsUrl: "",
            provider: "personaplex",
            ephemeralToken: nil,
            freeSecondsRemaining: nil,
            freeLimitKind: nil,
        )
    }

    func endConversation(
        sessionId _: String, inputTokens _: Int?, outputTokens _: Int?,
    ) async throws -> EndResponse {
        EndResponse(sessionId: "", durationSeconds: 0)
    }

    func appendTranscript(
        sessionId _: String,
        speaker _: String,
        text _: String,
        startedAt _: Date,
        endedAt _: Date,
    ) async throws {}

    func recordColdStart(durationMs: Int, phaseTimings: ColdStartTimings, sessionId: String) async throws {
        coldStartCalls.append((durationMs, phaseTimings, sessionId))
    }

    func recordPitchRange(sessionId _: String, minHz _: Float, maxHz _: Float) async throws {}

    func recordAIEmotions(
        sessionId _: String, laugh _: Int, cheer _: Int, gasp _: Int, sigh _: Int, groan _: Int,
    ) async throws {}

    func recordSessionError(sessionId _: String?, provider _: String, reason _: String) async throws {}

    func recordToolCall(sessionId _: String?, name _: String, query _: String?) async throws {}

    func recordSessionEnd(sessionId _: String, reason _: String) async throws {}

    func reportAudioUploadFailed(sessionId _: String, source _: String, bytes _: Int, reason _: String) async {}

    func uploadMicAudio(sessionId _: String, deflatedWav _: Data) async throws {}

    func uploadModelAudio(sessionId _: String, deflatedWav _: Data) async throws {}

    func getPersonas(search _: String?, sort _: String) async throws -> [PersonaDTO] {
        []
    }

    func getEntitlement() async throws -> Entitlement {
        Entitlement(
            isPremium: true,
            trialActive: false,
            trialEndsAt: nil,
            freeMinutesRemainingToday: 10,
            freeMinutesRemainingThisWeek: 30,
            freeMinutesPerDayCap: 10,
            freeMinutesPerWeekCap: 30,
            premiumEndsAt: nil,
        )
    }

    func recallFacts(query _: String) async throws -> String {
        ""
    }

    func recallConversations(query _: String) async throws -> String {
        ""
    }

    func searchTranscripts(query _: String) async throws -> String {
        ""
    }

    func webFetch(url _: String) async throws -> String {
        ""
    }
}

final class ColdStartReporterTests: XCTestCase {
    /// Once the inboundAudio stream yields its first chunk, the reporter must:
    /// 1. POST exactly one cold_start_complete event.
    /// 2. Compute phase timings (each phase delta) from the four timestamps it was given.
    /// 3. Stop consuming further audio chunks.
    func testReportsOnceOnFirstAudio() async throws {
        let backend = RecordingColdStartBackend()
        let (audioStream, audioCont) = AsyncStream.makeStream(of: Data.self)
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        let tGather = t0.addingTimeInterval(0.2)
        let tStart = tGather.addingTimeInterval(0.4)
        let tConnect = tStart.addingTimeInterval(0.3)
        ColdStartReporter.scheduleReport(
            backend: backend,
            inboundAudio: audioStream,
            sessionId: "S-1",
            t0: t0,
            tGatherEnd: tGather,
            tStartEnd: tStart,
            tConnectEnd: tConnect,
        )
        audioCont.yield(Data([0xAA]))
        audioCont.yield(Data([0xBB]))
        audioCont.finish()

        // Wait for the detached task to publish the call. Reporter task runs at .background priority, which can be starved on a busy test runner — give it generous time to land before declaring failure.
        var calls: [(durationMs: Int, timings: ColdStartTimings, sessionId: String)] = []
        for _ in 0 ..< 200 {
            calls = await backend.coldStartCalls
            if !calls.isEmpty { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(calls.count, 1, "exactly one cold_start_complete per session")
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.sessionId, "S-1")
        // The deltas the reporter feeds into the timings struct are functions of (t0…tConnect). Floating-point math on
        // TimeInterval can land 1ms low (Int(0.4 * 1000) sometimes truncates 399.999... → 399), so allow ±1ms.
        XCTAssertTrue((199 ... 201).contains(call.timings.gatherContextMs), "got \(call.timings.gatherContextMs)")
        XCTAssertTrue((399 ... 401).contains(call.timings.backendStartMs), "got \(call.timings.backendStartMs)")
        XCTAssertTrue((299 ... 301).contains(call.timings.websocketConnectMs), "got \(call.timings.websocketConnectMs)")
        // firstAudioMs is whatever real wall-clock elapses between scheduling + first yield. Just lower-bound it.
        XCTAssertGreaterThanOrEqual(call.timings.firstAudioMs, 0)
        // Same rounding tolerance for the total.
        XCTAssertGreaterThanOrEqual(call.durationMs, 200 + 400 + 300 - 3)
    }

    /// If the inboundAudio stream finishes without yielding anything (server died before sending), the reporter must stay silent — never invent a cold-start event with garbage numbers.
    func testNoReportWhenStreamFinishesWithoutAudio() async throws {
        let backend = RecordingColdStartBackend()
        let (audioStream, audioCont) = AsyncStream.makeStream(of: Data.self)
        let now = Date()
        ColdStartReporter.scheduleReport(
            backend: backend,
            inboundAudio: audioStream,
            sessionId: "S-2",
            t0: now,
            tGatherEnd: now,
            tStartEnd: now,
            tConnectEnd: now,
        )
        audioCont.finish()
        try await Task.sleep(nanoseconds: 300_000_000)
        let calls = await backend.coldStartCalls
        XCTAssertEqual(calls.count, 0)
    }
}
