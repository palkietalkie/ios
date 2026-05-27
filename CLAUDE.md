# Palkie Talkie — iOS

Terminology: see /JARGON.md at the repo root.

iOS client repo. Pure streaming client — no on-device inference, no on-device DB. Shared product positioning, business model, cost simulation, GTM, team/fundraising, infrastructure accounts, end-to-end voice loop (which spans iOS + backend + provider) live in the parent `../CLAUDE.md`. Server-side concerns live in `../backend/CLAUDE.md`.

## #1 Design Principle: Latency Is Everything

Real-time voice conversation cannot tolerate delays. If the user finishes speaking and waits even a beat too long, the experience is broken. Every iOS-side choice (audio session config, WS framing, scheduling, UI re-renders) must hold to a 1.5s "open → first AI audio" budget and zero perceptible gap during the conversation.

## Tech Stack

| Layer         | Choice                              | Package                                                         |
| ------------- | ----------------------------------- | --------------------------------------------------------------- |
| Platform      | Swift / SwiftUI, iOS 26+            | —                                                               |
| State         | `@State` / `@Observable` in memory  | Backend is the only durable store (Neon + AuraDB + Pinecone). No on-device DB. |
| Audio         | AVAudioEngine + AVAudioPlayerNode   | AVFoundation                                                    |
| Audio Session | `.playAndRecord` + `.default` mode  | Session-wide voice processing OFF; mic-input AEC enabled surgically via `inputNode.setVoiceProcessingEnabled(true)`. See `Audio/AudioSession.swift` for the rationale (the `.videoChat` mode's AGC noise-gate silences sub-`-11dBFS` output, which killed OpenAI's quieter TTS). |
| Networking    | URLSessionWebSocketTask             | Foundation (built-in)                                           |
| Opus codec    | swift-opus                          | github.com/alta/swift-opus (pinned `revision:` — PersonaPlex audio path only) |
| Auth          | Clerk iOS SDK (`ClerkKit`)          | clerk.com                                                       |
| Payments      | StoreKit 2                          | Built-in                                                        |
| Push          | UNUserNotificationCenter + APNs     | Built-in; APNs payloads minted server-side                      |

Inference / provider switch / pricing live server-side. iOS knows about it only via the `provider` field on `/conversation/start` response and picks the correct WS wire protocol from that.

## Architecture (iOS as client)

iOS does NOT run any inference. The full conversational AI — listen + speak — happens server-side. iOS is purely:

1. Captures mic audio, encodes for the active provider's wire protocol.
2. Streams it over a WebSocket to the inference server.
3. Decodes inbound audio frames, plays them on `AVAudioPlayerNode`.
4. Surfaces the live transcript and conversation state in SwiftUI.

```text
mic ─→ encode (Opus | raw PCM16) ─→ WS ─→ [server-side inference]
                                          │
speaker ←─ decode (Opus | raw PCM16) ←─ WS ┘
```

Two provider paths share the `RealtimeClient` protocol (`Network/RealtimeClient.swift`):

- PersonaPlex (`Network/PersonaPlexClient.swift`, `Network/PersonaPlexSession.swift`) — binary Ogg-Opus frames over WS. Server handshake byte `\x00` gates the audio pump. Barge-in handled server-side.
- OpenAI Realtime (`Network/OpenAIRealtimeClient.swift`) — JSON event frames over WS. Audio bytes in/out as base64-PCM16. `session.created` event gates the audio pump. Barge-in is iOS-side: `input_audio_buffer.speech_started` event triggers `bargeIn` stream → `streamer.interruptPlayback()` which drops queued buffers.

The orchestrator (`SessionController.swift`) is provider-agnostic — it talks to `RealtimeClient` and lets the concrete implementations handle wire-protocol differences.

## Conversation flow

iOS-side behavior + state machine. Cross-cutting protocol (WS framing, provider handshakes, server-side steps) lives in root `/CLAUDE.md` § End-to-end voice loop.

1. App opens. Talk is the default tab. `ConversationView.task` fires `SessionController.start()` — no button press. Same trigger fires whenever user switches back to Talk from another tab AND `phase == .idle`.
2. `ContextGatherer` collects the user's here-and-now in parallel:
   - Local date / time / day-of-week (device clock)
   - Location + city (Core Location, permission-gated)
   - Weather + temperature (open-meteo, keyed by location)
   - Today's calendar events (Integrations → Google Calendar)
   The persona inhabits the same moment as the user. Same time, same city, same weather. The AI shares the moment ("cold one this morning"), not observes from outside ("chilly out there in SF"). Backend's `prompt_assembler` frames these as the persona's here-and-now.
3. `POST /conversation/start` to Fly with Clerk JWT (~50-100ms RTT + ~200-400ms backend context assembly). Backend assembles the system prompt (persona + situational context + KG + profile + last-session recall + instruction to OPEN the conversation in character) and returns `{provider, wsUrl, voiceId, ephemeralToken, textPrompt, sessionId}`.
4. iOS opens the WS using `response.wsUrl` (~50-100ms TLS + upgrade). Wires the right `RealtimeClient` based on `response.provider` (PersonaPlex or OpenAI).
5. Wait for server-ready signal (`\x00` byte for PersonaPlex; `session.created` event for OpenAI). Until then, "Loading your tutor..." `LoadingTipsView` flippable tips screen — also hides cold-start latency on PersonaPlex's Modal scale-to-zero path.
6. Server-ready → start `AudioStreamer` (AVAudioEngine + mic tap + playerNode). On the OpenAI path, also send `response.create` so the AI opens immediately without waiting for user audio.
7. AI speaks the opening turn — addressing user by name, callback to recent context, full first turn (not a "hello"). Audio streams to playerNode, transcript deltas aggregate into the captions UI.
8. User responds whenever ready. Mic audio streams continuously.
9. Full-duplex: AI listens + generates in parallel. Barge-in: PersonaPlex handles server-side (Inner Monologue); OpenAI emits `input_audio_buffer.speech_started`, iOS yields `bargeIn` → `streamer.interruptPlayback()` drops queued AI audio.
10. Each speaker block (one continuous turn from user OR persona) flushes as a single `POST /conversation/<session_id>/transcript` row on speaker switch — one row per TURN, not per stream emission. Live transcript UI still shows incremental deltas.
11. ConversationView disappears (tab switch or backgrounding) or app closes → `SessionController.end()` flushes the pending turn, calls `POST /conversation/<session_id>/end`. Backend queues post-session NLP pipelines (transcript_analysis, phrase_extraction, mistake_detection, kg_extraction).

Phase machine (`SessionController.Phase`):

```text
.idle → .gatheringContext → .startingSession → .connecting → .live → .ending → .idle
                                                         ↘ .error(reason)
```

Error states surface in the mic view (red mic + error string). User can tap to retry; SessionController re-enters `.idle` and `.task` re-fires.

Latency budget: app open → first AI audio. Target 1.5s on a warm server. Per-phase ms (gather_context, backend_start, websocket_connect, first_audio) are POSTed to backend `/events` via `SessionController.scheduleColdStartReport` for p50 / p95 tracking. Cold starts on PersonaPlex Modal scale-to-zero (~5-8s) are user-visible only as the "Loading your tutor..." tips; OpenAI has no cold start.

## Reading the iPhone screen / device logs

Reading device logs from the connected iPhone is the default debugging move, not a fallback. Don't guess at iOS errors when an iPhone is on the cable — pull the logs first.

```bash
# Stream live (Ctrl-C to stop). Filter by Swift Logger subsystem.
log stream --device --predicate 'subsystem == "com.palkietalkie"' --level info

# One-shot capture via libimobiledevice (more lines, less filtering):
idevicesyslog -p PalkieTalkie -o /tmp/pt.log --no-colors

# Filter for our custom Logger emissions:
grep "PalkieTalkie.debug.dylib" /tmp/pt.log
```

Caveats:

- Only `os.Logger.error(...)` consistently surfaces in `idevicesyslog`. `.info` / `.debug` get filtered out by default. When debugging on device, temporarily promote diagnostics to `.error`, then back to `.info` once fixed.
- `String(describing: error)` rendered into a SwiftUI view does NOT automatically land in oslog. Wire explicit `Logger(subsystem: "com.palkietalkie", category: "...").error("...")` in `catch` blocks where `phase = .error(...)` is set.
- `log stream --device` requires the device to be paired and Xcode-trusted. `xcrun devicectl list devices` should show `State=connected`.

## Development Notes

- UI language: default = device locale; user can override in app settings.
- AVAudioEngine stays running for the entire conversation — never stop/start between turns. Engine startup costs ~200ms and triggers audio glitches.
- Audio session mode is `.default`, NOT `.voiceChat` / `.videoChat`. Those modes apply iOS's voice-processing AGC + noise gate at the session level, which silences sub-`-11dBFS` output as "background noise" and killed OpenAI's quieter TTS in earlier builds. AEC for the mic side is enabled surgically via `inputNode.setVoiceProcessingEnabled(true)` in `AudioStreamer.start()`.
- Clerk iOS SDK is `ClerkKit` (v1.x — import via `import ClerkKit`, not `import Clerk`). `Clerk.configure(publishableKey:)` is a static method now (not on `.shared`); `clerk.auth.signOut()` replaces `Clerk.shared.signOut()`.

## Setup (once per clone)

```shell
./scripts/setup.sh
```

Installs the pre-commit hook, runs `xcodegen generate`, and verifies `xcodegen` + `xcodebuild` are on PATH.

## LGTM Workflow

CRITICAL: NEVER start without explicit user request. PR must be clean, don't ignore failures.

1. `git fetch origin main && git merge origin/main`
2. `git commit -m "<one-liner subject>"`, user has already run `git add` before saying "lgtm"
   - Pre-commit hook runs automatically (see `scripts/git/pre_commit_hook.sh`): `xcodegen generate` if `project.yml` staged, then `xcodebuild` build if any `.swift` or `project.yml` staged
   - One-liner subject only. No body paragraphs. PR body carries long-form context.
   - NO co-author lines, NO `[skip ci]`
   - If hook fails: fix, re-stage, commit again. Don't stage other sessions' files.
3. Check for existing PR: `gh pr list --head $(git branch --show-current) --state open`, if exists, STOP and ask
4. `git push`
5. `gh pr create --title "<technical, descriptive title>" --body "" --assignee @me`, title is enough; no body until product launches.
