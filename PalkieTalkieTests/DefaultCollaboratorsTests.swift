@testable import PalkieTalkie
import XCTest

/// Cover the production default-impl factories declared in SessionCollaborators.swift. Each just constructs a real underlying type and returns it — exercising init is enough for the file-coverage instrumentation. The body-level concerns (audio session, websocket, etc.) are covered by their own integration-style tests on the underlying types.
@MainActor
final class DefaultCollaboratorsTests: XCTestCase {
    func testDefaultPersonaPlexSessionFactoryMakesSession() {
        let factory = DefaultPersonaPlexSessionFactory()
        _ = factory.makeSession()
    }

    func testDefaultOpenAIRealtimeClientFactoryMakesClient() {
        let factory = DefaultOpenAIRealtimeClientFactory()
        _ = factory.makeClient(instructions: nil)
        _ = factory.makeClient(instructions: "test")
    }

    // `DefaultMicrophonePermission.requestMicrophonePermission` and `DefaultAudioStreamerFactory.makeStreamer` both call into AVAudio APIs that fail on the simulator without microphone hardware. They're covered by host-app launches; unit tests would crash on the engine precondition.
}
