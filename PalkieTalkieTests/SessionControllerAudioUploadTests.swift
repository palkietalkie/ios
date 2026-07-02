@testable import PalkieTalkie
import XCTest

/// Drives SessionController.end()'s audio-upload branches. Each test stages a wav file on disk, points the FakeAudioStreamer's recordedSessionAudioURL / recordedModelAudioURL at it, runs the start → end flow, and asserts the backend's uploadMicAudio / uploadModelAudio calls fired.
@MainActor
final class SessionControllerAudioUploadTests: XCTestCase {
    private func makeWav(named name: String, bytes: Int = 200) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).wav")
        try Data(repeating: 0xAA, count: bytes).write(to: url)
        return url
    }

    private func makeBackend() -> FakeConversationBackend {
        FakeConversationBackend(
            startResponse: StartResponse(
                sessionId: "srv-upload-1",
                textPrompt: "hi",
                voiceId: "v1",
                wsUrl: "wss://test",
                provider: "personaplex",
                ephemeralToken: nil,
                freeSecondsRemaining: nil,
                freeLimitKind: nil,
            ),
            endResponse: EndResponse(sessionId: "srv-upload-1", durationSeconds: 10),
        )
    }

    /// A throwaway outbox directory per controller so tests never read/write the real caches folder or collide with each other.
    private func makeOutbox() -> AudioUploadOutbox {
        AudioUploadOutbox(
            dir: FileManager.default.temporaryDirectory
                .appendingPathComponent("outbox-\(UUID().uuidString)", isDirectory: true),
        )
    }

    private func makeController(
        backend: FakeConversationBackend,
        streamer: FakeAudioStreamer,
        outbox: AudioUploadOutbox,
    ) -> SessionController {
        SessionController(
            context: FakeContextGatherer(context: ConversationContext(
                localISOTime: "2025-01-01T00:00:00Z",
                timezone: "UTC",
                lat: nil, lon: nil, city: nil, calendarEvents: [],
            )),
            backend: backend,
            micPermission: StubMicPermission(shouldThrow: false),
            streamerFactory: StubAudioStreamerFactory(streamer: streamer),
            sessionFactory: StubSessionFactory(session: FakePersonaPlexSession()),
            outbox: outbox,
        )
    }

    func testEndUploadsBothMicAndModelAudioWhenURLsPresent() async throws {
        let backend = makeBackend()
        let streamer = FakeAudioStreamer()
        let micURL = try makeWav(named: "mic")
        let modelURL = try makeWav(named: "model")
        streamer.sessionAudioURL = micURL
        streamer.modelAudioURL = modelURL
        defer {
            try? FileManager.default.removeItem(at: micURL)
            try? FileManager.default.removeItem(at: modelURL)
        }
        let controller = makeController(backend: backend, streamer: streamer, outbox: makeOutbox())
        await controller.start()
        await controller.end()
        XCTAssertEqual(backend.micUploads.count, 1, "mic upload should have fired")
        XCTAssertEqual(backend.modelUploads.count, 1, "model upload should have fired")
        XCTAssertEqual(backend.micUploads.first?.0, "srv-upload-1")
        // Deflated wav should be smaller than the 200-byte original (mostly zeros compress well).
        XCTAssertGreaterThan(backend.micUploads.first?.1 ?? 0, 0)
    }

    func testEndSkipsBothUploadsWhenStreamerHasNoURLs() async {
        let backend = makeBackend()
        let streamer = FakeAudioStreamer()
        // sessionAudioURL and modelAudioURL both nil — both guards trip, no uploads fire.
        let controller = makeController(backend: backend, streamer: streamer, outbox: makeOutbox())
        await controller.start()
        await controller.end()
        XCTAssertEqual(backend.micUploads.count, 0)
        XCTAssertEqual(backend.modelUploads.count, 0)
    }

    func testEndSkipsModelUploadWhenOnlyMicURLPresent() async throws {
        let backend = makeBackend()
        let streamer = FakeAudioStreamer()
        let micURL = try makeWav(named: "mic-only")
        streamer.sessionAudioURL = micURL
        streamer.modelAudioURL = nil
        defer { try? FileManager.default.removeItem(at: micURL) }
        let controller = makeController(backend: backend, streamer: streamer, outbox: makeOutbox())
        await controller.start()
        await controller.end()
        XCTAssertEqual(backend.micUploads.count, 1)
        XCTAssertEqual(backend.modelUploads.count, 0, "model URL nil → guard skips upload")
    }

    func testEndSwallowsMicUploadErrorAndContinuesToModel() async throws {
        let backend = makeBackend()
        backend.micUploadError = NSError(domain: "test", code: 1)
        let streamer = FakeAudioStreamer()
        let micURL = try makeWav(named: "mic-fail")
        let modelURL = try makeWav(named: "model-after-fail")
        streamer.sessionAudioURL = micURL
        streamer.modelAudioURL = modelURL
        defer {
            try? FileManager.default.removeItem(at: micURL)
            try? FileManager.default.removeItem(at: modelURL)
        }
        let controller = makeController(backend: backend, streamer: streamer, outbox: makeOutbox())
        await controller.start()
        await controller.end()
        XCTAssertEqual(backend.modelUploads.count, 1, "model upload still fires after mic upload throws")
    }

    func testEndSkipsMicUploadWhenWavFileIsEmpty() async throws {
        let backend = makeBackend()
        let streamer = FakeAudioStreamer()
        let micURL = try makeWav(named: "empty-mic", bytes: 0)
        streamer.sessionAudioURL = micURL
        defer { try? FileManager.default.removeItem(at: micURL) }
        let controller = makeController(backend: backend, streamer: streamer, outbox: makeOutbox())
        await controller.start()
        await controller.end()
        XCTAssertEqual(backend.micUploads.count, 0, "empty wav → guard !wavData.isEmpty skips upload")
    }

    func testEndDeletesLocalWavAfterUpload() async throws {
        let backend = makeBackend()
        let streamer = FakeAudioStreamer()
        let micURL = try makeWav(named: "delete-after")
        streamer.sessionAudioURL = micURL
        let controller = makeController(backend: backend, streamer: streamer, outbox: makeOutbox())
        await controller.start()
        await controller.end()
        XCTAssertFalse(FileManager.default.fileExists(atPath: micURL.path), "local wav must be deleted after upload")
    }

    func testMissingMicURLStillUploadsModelAudio() async throws {
        // Regression (Nao's session: model audio present, mic absent). The mic upload used to CHAIN the model upload from inside its own function, so a nil mic URL (recording never finalized) hit the mic guard's early return and silently dropped the model track too. They're independent steps now.
        let backend = makeBackend()
        let streamer = FakeAudioStreamer()
        streamer.sessionAudioURL = nil
        let modelURL = try makeWav(named: "model-no-mic")
        streamer.modelAudioURL = modelURL
        defer { try? FileManager.default.removeItem(at: modelURL) }
        let controller = makeController(backend: backend, streamer: streamer, outbox: makeOutbox())
        await controller.start()
        await controller.end()
        XCTAssertEqual(backend.micUploads.count, 0, "no mic URL → no mic upload")
        XCTAssertEqual(
            backend.modelUploads.count,
            1,
            "model upload is independent of the mic track and must still fire",
        )
    }

    func testEmptyMicWavStillUploadsModelAudio() async throws {
        // Same decoupling, via the empty-file early return: a zero-byte mic wav must not suppress the model upload.
        let backend = makeBackend()
        let streamer = FakeAudioStreamer()
        let micURL = try makeWav(named: "empty-mic-with-model", bytes: 0)
        let modelURL = try makeWav(named: "model-after-empty-mic")
        streamer.sessionAudioURL = micURL
        streamer.modelAudioURL = modelURL
        defer {
            try? FileManager.default.removeItem(at: micURL)
            try? FileManager.default.removeItem(at: modelURL)
        }
        let controller = makeController(backend: backend, streamer: streamer, outbox: makeOutbox())
        await controller.start()
        await controller.end()
        XCTAssertEqual(backend.micUploads.count, 0, "empty mic wav → mic upload skipped")
        XCTAssertEqual(backend.modelUploads.count, 1, "model upload independent of the empty mic file")
    }

    func testFailedUploadIsRetainedAndRetriedOnNextFlush() async throws {
        // The core fix. The old path deleted each wav right after attempting its POST, success or fail, so a single failed upload lost that recording forever — the likely "model present, mic absent" mechanism. Now a failed track stays queued and a later flush (next session end / next app launch, once connectivity is back) delivers it.
        let backend = makeBackend()
        backend.micUploadError = NSError(domain: "test", code: 1)
        let streamer = FakeAudioStreamer()
        let micURL = try makeWav(named: "retry-mic")
        streamer.sessionAudioURL = micURL
        defer { try? FileManager.default.removeItem(at: micURL) }
        let outbox = makeOutbox()
        let controller = makeController(backend: backend, streamer: streamer, outbox: outbox)
        await controller.start()
        await controller.end()
        // First attempt failed: the payload is retained (not lost) and the failure is reported so it's visible server-side.
        XCTAssertEqual(outbox.pending().count, 1, "failed payload is retained for retry, not deleted")
        XCTAssertEqual(backend.audioUploadFailedReports.count, 1, "the failure is reported as telemetry")
        XCTAssertEqual(backend.audioUploadFailedReports.first?.source, "mic")
        // Connectivity recovers; the next flush delivers the previously-failed payload and drains the queue.
        backend.micUploadError = nil
        await controller.flushAudioOutbox()
        XCTAssertEqual(outbox.pending().count, 0, "retry delivered the payload; queue drained")
    }
}
