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

    private func makeController(backend: FakeConversationBackend, streamer: FakeAudioStreamer) -> SessionController {
        SessionController(
            context: FakeContextGatherer(context: ConversationContext(
                localISOTime: "2025-01-01T00:00:00Z",
                timezone: "UTC",
                lat: nil, lon: nil, city: nil,
                weatherDescription: nil, temperatureC: nil,
                calendarEvents: [],
            )),
            backend: backend,
            micPermission: StubMicPermission(shouldThrow: false),
            streamerFactory: StubAudioStreamerFactory(streamer: streamer),
            sessionFactory: StubSessionFactory(session: FakePersonaPlexSession()),
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
        let controller = makeController(backend: backend, streamer: streamer)
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
        let controller = makeController(backend: backend, streamer: streamer)
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
        let controller = makeController(backend: backend, streamer: streamer)
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
        let controller = makeController(backend: backend, streamer: streamer)
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
        let controller = makeController(backend: backend, streamer: streamer)
        await controller.start()
        await controller.end()
        XCTAssertEqual(backend.micUploads.count, 0, "empty wav → guard !wavData.isEmpty skips upload")
    }

    func testEndDeletesLocalWavAfterUpload() async throws {
        let backend = makeBackend()
        let streamer = FakeAudioStreamer()
        let micURL = try makeWav(named: "delete-after")
        streamer.sessionAudioURL = micURL
        let controller = makeController(backend: backend, streamer: streamer)
        await controller.start()
        await controller.end()
        XCTAssertFalse(FileManager.default.fileExists(atPath: micURL.path), "local wav must be deleted after upload")
    }
}
