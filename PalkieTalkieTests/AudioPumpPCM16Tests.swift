import Foundation
@testable import PalkieTalkie
import XCTest

/// PCM16 pump tests — mirror the Opus / PersonaPlex variant in AudioPumpTests. Verifies the OpenAI path correctly waits
/// on the realtime client's handshake before forwarding audio, plus barge-in signals trigger interruptPlayback.
@MainActor
final class AudioPumpPCM16Tests: XCTestCase {
    func testPCM16PumpWaitsForServerReadyBeforeSendingAudio() async throws {
        let client = HandshakeGatedRealtimeClient()
        let streamer = PCM16ReplayStreamer(frames: [Data([0x01, 0x02]), Data([0x03, 0x04])])

        let pump = AudioPump()
        await pump.startPCM16(streamer: streamer, client: client)

        try await Task.sleep(for: .milliseconds(150))
        let beforeHandshake = await client.recordedAudio
        XCTAssertEqual(beforeHandshake, [], "pump must not send before waitForServerReady resolves")

        await client.signalReady()
        try await Task.sleep(for: .milliseconds(150))
        let afterHandshake = await client.recordedAudio
        XCTAssertEqual(afterHandshake, [Data([0x01, 0x02]), Data([0x03, 0x04])])

        await pump.stop()
    }

    func testPCM16PumpForwardsInboundAudioToStreamer() async throws {
        let client = HandshakeGatedRealtimeClient()
        let streamer = PCM16ReplayStreamer(frames: [])
        let pump = AudioPump()
        await pump.startPCM16(streamer: streamer, client: client)
        await client.signalReady()

        await client.emitAudio(Data([0xAA, 0xBB]))
        await client.emitAudio(Data([0xCC]))
        try await Task.sleep(for: .milliseconds(150))

        let played = streamer.played
        XCTAssertEqual(played, [Data([0xAA, 0xBB]), Data([0xCC])])
        await pump.stop()
    }

    func testPCM16PumpForwardsBargeInToInterruptPlayback() async throws {
        let client = HandshakeGatedRealtimeClient()
        let streamer = PCM16ReplayStreamer(frames: [])
        let pump = AudioPump()
        await pump.startPCM16(streamer: streamer, client: client)
        await client.signalReady()

        await client.emitBargeIn()
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(streamer.interruptCount, 1)
        await pump.stop()
    }
}

// MARK: - Fakes

private actor HandshakeGatedRealtimeClient: RealtimeClient {
    nonisolated(unsafe) var recordedAudio: [Data] = []

    private let (audioStream, audioCont) = AsyncStream.makeStream(of: Data.self)
    private let (transcriptStream, _) = AsyncStream.makeStream(of: TranscriptChunk.self)
    private let (errorStream, _) = AsyncStream.makeStream(of: String.self)
    private let (bargeInStream, bargeInCont) = AsyncStream.makeStream(of: Void.self)

    private var handshakeFired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open(wsUrl _: String, ephemeralToken _: String?) async throws {}

    func close() async {
        audioCont.finish()
        bargeInCont.finish()
    }

    func send(audio chunk: Data) async throws {
        recordedAudio.append(chunk)
    }

    func waitForServerReady() async {
        if handshakeFired { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            waiters.append(c)
        }
    }

    func signalReady() {
        handshakeFired = true
        let resumers = waiters
        waiters.removeAll()
        for r in resumers {
            r.resume()
        }
    }

    func emitAudio(_ data: Data) {
        audioCont.yield(data)
    }

    func emitBargeIn() {
        bargeInCont.yield(())
    }

    nonisolated var inboundAudio: AsyncStream<Data> {
        get async { audioStream }
    }

    nonisolated var transcript: AsyncStream<TranscriptChunk> {
        get async { transcriptStream }
    }

    nonisolated var errors: AsyncStream<String> {
        get async { errorStream }
    }

    nonisolated var bargeIn: AsyncStream<Void> {
        get async { bargeInStream }
    }

    func injectSystemHint(_: String) async {}
}

private final class PCM16ReplayStreamer: PCM16AudioStreamerType, @unchecked Sendable {
    nonisolated(unsafe) var played: [Data] = []
    nonisolated(unsafe) var interruptCount = 0
    private let stream: AsyncStream<Data>

    init(frames: [Data]) {
        stream = AsyncStream<Data> { continuation in
            for f in frames {
                continuation.yield(f)
            }
            continuation.finish()
        }
    }

    var pcm16InputChunks: AsyncStream<Data> {
        get async { stream }
    }

    func playPCM16(_ pcm16Bytes: Data) async {
        played.append(pcm16Bytes)
    }

    func interruptPlayback() async {
        interruptCount += 1
    }
}
