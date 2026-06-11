import Foundation

/// Audio-streamer surface used by `AudioPump` AND `SessionController`'s end-of-session upload path. Lets the pump + end() flow be unit-tested with a fake streamer that doesn't touch AVAudioEngine.
protocol AudioStreamerType: AnyObject, Sendable {
    var inputChunks: AsyncStream<Data> { get async }
    nonisolated var pitchTracker: PitchTracker { get }
    func playOutput(_ opusPacket: Data) async
    /// URL of the mic-side wav file from the just-finished session, if any. Read after stop() in end() so SessionController can gzip + upload + delete. Nil when no session ran (e.g. very early error).
    var recordedSessionAudioURL: URL? { get async }
    /// URL of the model-output wav file. Same lifecycle as above.
    var recordedModelAudioURL: URL? { get async }
    /// Tear down the audio graph (mic tap removed, engine stopped, queued buffers cleared). Safe to call when never started.
    func stop() async
}

extension AudioStreamer: AudioStreamerType {}

/// PCM16 variant for the OpenAI Realtime path. Mic side emits raw PCM16 frames; speaker side accepts raw PCM16 chunks. Separate protocol so the OpenAI-specific pump doesn't accidentally end up running over the Opus path (or vice versa).
protocol PCM16AudioStreamerType: AnyObject, Sendable {
    var pcm16InputChunks: AsyncStream<Data> { get async }
    func playPCM16(_ pcm16Bytes: Data) async
    /// Stop and clear the player's queued buffers so the user hears immediate silence when they barge in over the AI. Player should be ready to receive new buffers immediately after.
    func interruptPlayback() async
}

extension AudioStreamer: PCM16AudioStreamerType {}

/// Pumps audio in both directions between an `AudioStreamerType` and a `PersonaPlexSessionType`. Separating this from `SessionController` keeps the orchestrator free of audio plumbing — and lets us test the pump's start/stop behaviour without booting AVAudioEngine.
actor AudioPump {
    private var tasks: [Task<Void, Never>] = []

    /// Starts mic→server and server→speaker pumps. Each runs until either side finishes its async stream or `stop()` is called.
    func start(streamer: AudioStreamerType, session: PersonaPlexSessionType) async {
        await stop()

        let micTask = Task.detached {
            // Block until the server sends its handshake byte. Sending audio earlier breaks sphn's Ogg-Opus stream parsing because the server's recv_loop only starts after step_system_prompts_async (~30s on cold start). See PersonaPlexClient.waitForServerHandshake.
            await session.waitForServerReady()
            let stream = await streamer.inputChunks
            for await chunk in stream {
                try? await session.send(audio: chunk)
            }
        }
        let speakerTask = Task.detached {
            let audio = await session.inboundAudio
            for await packet in audio {
                await streamer.playOutput(packet)
            }
        }
        tasks = [micTask, speakerTask]
    }

    /// PCM16-mode variant for any `RealtimeClient` (OpenAI today; future PCM16-speaking providers tomorrow). Mic emits raw PCM16 frames straight onto the wire; server-side PCM16 chunks go through `playPCM16`.
    func startPCM16(streamer: PCM16AudioStreamerType, client: RealtimeClient) async {
        await stop()

        let micTask = Task.detached {
            await client.waitForServerReady()
            let stream = await streamer.pcm16InputChunks
            for await chunk in stream {
                try? await client.send(audio: chunk)
            }
        }
        let speakerTask = Task.detached {
            let audio = await client.inboundAudio
            for await pcm in audio {
                await streamer.playPCM16(pcm)
            }
        }
        let bargeInTask = Task.detached {
            let signals = await client.bargeIn
            for await _ in signals {
                await streamer.interruptPlayback()
            }
        }
        tasks = [micTask, speakerTask, bargeInTask]
    }

    func stop() async {
        for task in tasks {
            task.cancel()
        }
        tasks.removeAll()
    }
}
