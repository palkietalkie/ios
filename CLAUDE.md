# Palkie Talkie — iOS

iOS app repo. Shared product positioning, ICP, GTM, business model, and team/fundraising live in the parent `../CLAUDE.md`.

## #1 Design Principle: Latency Is Everything

Every architectural decision must prioritize minimizing latency. Real-time voice conversation cannot tolerate delays, if the user finishes speaking and waits even a beat too long, the experience is broken. This applies to LLM inference, STT, TTS, and every layer in between.

## Tech Stack

| Layer         | Choice                              | Package                                  |
| ------------- | ----------------------------------- | ---------------------------------------- |
| Platform      | Swift / SwiftUI, iOS 26+            | —                                        |
| Audio         | AVAudioEngine + AVAudioPlayerNode   | AVFoundation                             |
| Audio Session | `.playAndRecord`, `.voiceChat` mode | Built-in echo cancellation               |
| Networking    | URLSessionWebSocketTask             | Foundation (built-in)                    |
| Auth          | Clerk iOS SDK                       | clerk.com                                |
| Local cache   | SwiftData                           | Built-in (iOS 17+)                       |
| Payments      | StoreKit 2                          | Built-in                                 |
| Push          | UNUserNotificationCenter + APNs     | Built-in; APNs via backend               |
| Inference     | PersonaPlex on Lambda Labs A100     | Server-side (see `../backend/`)          |

## Architecture

iOS app is a thin streaming client to PersonaPlex on a cloud A100. Full-duplex audio in and out — no on-device VAD / STT / LLM / TTS pipeline. PersonaPlex handles listen + speak concurrently in one model.

```text
iOS app                                  PersonaPlex server (A100)
─────────                                ───────────────────────
mic ─→ 24kHz audio chunks ─────────→  PersonaPlex
                                              ↓
speaker ←─ 24kHz audio chunks ──────  generated audio (Mimi-decoded)
```

No client-side state machine. Barge-in / interruption / overlap are handled natively by PersonaPlex's parallel-stream architecture.

## Conversation-start latency budget

Time from app open → user hears first audio chunk. Target ceiling: 1.5s. Anything past that feels broken.

Sequence:

1. App restores Clerk session from keychain (~10ms, local).
2. `POST /conversation/start` to Fly.io backend (~50-100ms RTT).
3. Backend queries AuraDB + Neon + weather API + calendar API in parallel; assembles text prompt (~200-400ms).
4. Backend returns text prompt to iOS.
5. iOS opens WebSocket to Lambda Labs with text prompt + Clerk JWT (~50-100ms).
6. Lambda spins up the session, PersonaPlex generates first audio chunk (~200-300ms).
7. iOS plays first audio chunk.

Realistic: 500ms-1s. Instrument every step.

## Conversation flow

1. App opens. Fetch last-used persona for this user (or default if first session).
2. Gather context the user actually feels right now:
   - Local date / time / day of week (from device clock).
   - Location: city, neighborhood (Core Location, with user permission).
   - Weather + temperature (weather API keyed to location).
   - Today's calendar events (from the Integrations layer).
   - From KG + profile: recent life events, frequently-referenced entities, current goals.
   Reason: the persona inhabits the same moment as the user. Same time, same city, same weather. The AI doesn't observe from outside ("chilly out there in SF") — it shares the moment ("cold one this morning"). The text prompt must frame these as the persona's own here-and-now, not as third-party data about the user.
3. Build text prompt: persona description + shared situational context (the persona is in the same time / city / weather as the user, not observing from elsewhere) + user-specific context (KG + profile + calendar) + an instruction to initiate the conversation by greeting the user by name.
4. Build voice prompt: the persona's stock voice (NATM1 / VARF3 / etc.) or custom voice prompt.
5. Open the audio stream to the PersonaPlex server. Send text prompt + voice prompt + empty user audio (silence).
6. PersonaPlex generates the opening greeting audio without waiting for user input. Stream plays through the iPhone speaker. User hears "Hey Wes, how was your 2pm sync with the engineering team?" the moment the app is ready.
7. User responds whenever ready. Mic audio streams to the server continuously.
8. PersonaPlex listens and generates in parallel. Audio chunks stream back continuously.
9. Pauses / interruptions / overlap handled by the model. No client logic.
10. Session ends on close or explicit stop. Server signals session boundary. Post-session batch jobs (transcript analysis, vocab and phrase aggregation, mistake detection, KG updates) run async on the backend.

## Project Structure

```text
PalkieTalkie/
├── PalkieTalkieApp.swift            # App entry point
├── Models/                          # SwiftData
│   ├── User.swift
│   ├── Persona.swift
│   ├── ConversationSession.swift
│   └── KGEntity.swift               # local cache of server KG
├── Audio/
│   ├── AudioStreamer.swift          # AVAudioEngine, 24kHz mic in / speaker out, chunking
│   └── AudioSession.swift           # AVAudioSession config
├── Network/
│   ├── PersonaPlexClient.swift      # WebSocket protocol to PersonaPlex (text + voice prompt + audio stream)
│   ├── BackendAPI.swift             # REST to FastAPI backend
│   └── ClerkAuth.swift              # Clerk wrapper
├── Views/
│   ├── ConversationView.swift       # Feature 1: main mic screen
│   ├── HistoryView.swift            # Past sessions
│   ├── PersonaPickerView.swift      # Feature 3: preset library
│   ├── PersonaCustomizeView.swift   # Feature 3: customize / override
│   ├── TalkAboutTodayView.swift     # Feature 4: quiz + news prompts
│   ├── StatsView.swift              # Feature 5: stats summary
│   ├── MistakesView.swift           # Feature 5 detail
│   ├── PhrasesView.swift            # Feature 5 detail
│   ├── CEFRDetailView.swift         # Feature 5 detail
│   ├── IntegrationsView.swift       # Feature 6
│   └── ProfileView.swift            # Feature 7: profile + KG editor
└── Resources/
    └── Personas/                    # preset persona definitions (voice id + text prompt)
```

## Development Notes

- Founder background: Wes is new to iOS / Swift. Strong in TypeScript/JavaScript, Python, and PostgreSQL. When suggesting Swift patterns, explain Swift-isms vs their TS/Python equivalents in chat, NOT in source-file comments. Wes wants education, but not basic-language explanation comments inside `.swift` files.
- Comment policy: comments explain WHY (intent, hidden constraint, non-obvious reason), never WHAT (mechanics, syntax, what code does). Well-named identifiers cover WHAT. Long TERMINOLOGY-style block comments don't belong in source files.
- UI language: default = device locale; user can override in app settings (independent of device locale, but flexible to user preference)
- Architecture: PersonaPlex (NVIDIA, Jan 2026, built on Moshi). Server-side speech-to-speech with persona conditioning (voice prompt + text prompt). 17 pre-built voices. Personas = stock voice + text-prompt character (Jimmy Carr is a character, not a voice — pair a stock British-male voice with a text prompt for his style). Commercial license. Cost simulation: section below. Sources: `./architecture-research.md`.
- PersonaPlex runs on a Lambda Labs A100 (~$1.10/hr).
- AVAudioEngine stays running at all times, never stop/start between turns.

## Inference cost simulation

PersonaPlex on Lambda Labs A100s.

Assumptions:

- A100 80GB on Lambda Labs (chosen provider): ~$1.10/hr.
- PersonaPlex 7B BF16, A100 ~150 effective TFLOPS at 40-50% MFU.
- Per-session compute: 17 streams × 12.5 Hz × 14e9 FLOPs/token ≈ 3 TFLOPS.
- Theoretical concurrent: 50/A100. Realistic in production (idle gaps, KV cache, cold start): 10-15/A100. Using 12.
- Per-session cost: $1.10 / 12 = $0.092/hr.

Per-user monthly inference cost by usage tier:

| Usage               | Hours/month | Inference cost |
| ------------------- | ----------- | -------------- |
| Light (15 min/day)  | 7.5         | $0.69          |
| Medium (30 min/day) | 15          | $1.38          |
| Heavy (60 min/day)  | 30          | $2.76          |
| Very heavy (90/d)   | 45          | $4.14          |

Add-ons at medium usage: bandwidth ~$0.03, storage ~$0.10, ops overhead ~$0.20. All-in: ~$2.20/mo.

Gross margin at $12.99/mo Individual:

- Year 1 (App Store 30%): net $9.09 → 76% margin at medium usage.
- Year 2+ (App Store 15%): net $11.04 → 80% margin.
- Heavy users (1h/day): margin drops to 59% / 66%. Needs a fair-use cap.
- Free tier (10 min/day): ~$0.45/mo inference, pure CAC.

Healthy SaaS economics.

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
