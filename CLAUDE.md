# Talking Heads

AI-powered English conversation tutor with persistent memory, character personas, and scenario-based practice.

## Vision

Replace the frustrating experience of ChatGPT voice mode, DuoLingo, and Speak App with a tutor that feels like talking to a real person who knows you.

## Problem

Adult English learners — especially Japanese working professionals targeting business fluency — have no good way to practice speaking on demand. Existing options each fail in distinct ways:

- AI conversation apps (Speak, Praktika, Loora): cloud latency, no memory across sessions, generic AI persona, scripted feel
- Generic AI voice (ChatGPT voice mode): not built for learning, awkward turn-taking, interrupts mid-thought, no memory, no curriculum
- Human tutors over video (Cambly): scheduling friction, no-show losses, requires camera-on / sit-down, tutors don't prepare lessons
- In-person schools (Berlitz, Phoenix Associates, Nichibei Eigo Gakuin): expensive, fixed schedule, doesn't fit a working adult's life
- Gamified apps (Duolingo, Babbel, Memrise, LingoDeer): tap-and-translate drills, not real speaking

Motivated learners stall. They know they need conversation practice. None of the options fit into their life *and* feel like talking to someone real.

## ICP (Ideal Customer Profile)

Primary: Japanese working professionals (25–40) targeting business English fluency. Has tried Duolingo, attended an English school in their 20s, possibly tried Cambly. Speaks intermediate English but stalls because real conversation practice doesn't fit their life.

Founder = prototype user: founder went through Berlitz, Phoenix Associates, Nichibei Eigo Gakuin, then Cambly, then ChatGPT voice mode + Speak App. Each failed for distinct reasons documented in [Competitors](#competitors).

Secondary (later): adult English learners globally with similar profiles — Korean, Chinese, European working professionals.

## Solution

TalkingHeads is an iOS app: an AI conversation tutor that runs entirely on-device.

Three product pillars:

### 1. Natural voice interaction
- Start immediately — no "are you there?" verification, no "let me know when you're ready" filler
- Stop talking instantly when the user starts speaking
- Begin responding immediately when the user finishes — no awkward silence
- Distinguish between pauses (thinking) and turn completion — don't interrupt mid-thought
- Handle background noise gracefully — resume seamlessly without losing context

### 2. Persistent memory
- Full history of past sessions
- Track vocabulary the user knows vs. doesn't know — spaced repetition of new words/idioms
- Adapt difficulty and topics based on history

### 3. Engaging learning
- Character Personas — pick who you talk with: real personalities (Jimmy Carr, Jimmy O Yang) or role-play scenarios (prosecutor, politician, police officer)
- Scenario-Based Practice — discuss real news (Epstein files, FOMC decisions); situational practice (job interviews, debates, negotiations)
- App suggests topics proactively — users shouldn't have to come up with them
- Introduce uncommon words, idioms, and expressions the user doesn't already use

## Competitors

Ordered from direct to far. Pain points are first-person from the founder.

| Name | URL | Description | What's not good for me |
|---|---|---|---|
| Speak | speak.com | AI English conversation app with roleplay scenarios | UI is in Japanese because I'm in Japan even though my iPhone is in English; have to tap every time to end my speech; character voice sounds dead; doesn't feel like anyone real; no memory across sessions — reset every time; couldn't try free speech without subscribing (had to subscribe just to research); free speech blocks free response by default |
| Praktika / Loora / Univerbal | praktika.ai, loora.ai, univerbal.app | AI voice conversation tutors | Cloud-based → latency; no persistent memory of the individual learner; generic "AI tutor" persona, not real personalities |
| ChatGPT voice mode | chatgpt.com | General-purpose AI voice chat | Verifies "are you there?" before I can start — irritating; says "let me know..." filler — disgusting; keeps talking after I start speaking; doesn't start responding when I finish; interrupts when I'm just pausing mid-thought; pauses when I nod or background noise hits and can't resume; no memory of our conversations at all |
| Airlearn | airlearn.com | AI language app (saw it on a YouTube Short by my favorite Russian female creator) | Forced me to pick a mother tongue at signup with no English option; I had to pick Japanese; entire UI then in Japanese — uninstalled |
| Cambly | cambly.com | On-demand 1:1 video lessons with human tutors | Reserving slots is a burden and stressful every time; tutor no-shows are frustrating; my own no-shows lost me credits — painful; requires camera on, so unusable for commute / walk / bath — have to sit down; most tutors don't prepare lessons and just ask "how can I help you today?" — that's not a service; the few with a template stop suggesting once I propose anything; quit eventually |
| ELSA Speak | elsaspeak.com | AI pronunciation scoring | Drill-based, not real conversation; narrow scope (pronunciation only) |
| Duolingo | duolingo.com | Gamified tap-and-translate language drills | Voice mode is slow and sluggish; speaking isn't their main service; no real conversation; no memory of *me* |
| Babbel / Memrise / LingoDeer | babbel.com, memrise.com, lingodeer.com | Structured language lessons | Same category as Duolingo — vocabulary apps, not speaking partners |
| Berlitz | berlitz.com | In-person language school (went at 22, sponsored by Barclays) | Same model as Phoenix below — in-person only, fixed schedule, expensive, not on-demand |
| Phoenix Associates | phoenix-academy.co.jp | In-person language school (went at 22, sponsored by Barclays) | Professional teachers, heavy textbook homework, in-person speaking/listening drills — rigorous but in-person only and high commitment |
| Nichibei Eigo Gakuin | nichibei.ac.jp | In-person English school in Japan (went at 22, paid myself) | More casual and relaxed — not serious enough for real progress; in-person only |

## GTM (Go-to-Market)

*To be filled in.*

Suggested sub-sections to cover:
- Wedge — which user persona we acquire first, and through which channel
- Launch channels — App Store, Product Hunt, Japanese tech press, YouTube creators (esp. language-learning creators), TikTok / Reels
- Pricing model — freemium vs. subscription vs. one-time; price point benchmarked against Cambly (~$10/mo for 15 min/day) and Speak (~$20/mo)
- Acquisition loops — referrals, content (vocabulary insights from sessions?), share-a-conversation
- Partnerships — corporate English-training budgets (Japanese enterprises), schools (Berlitz/ECC alumni)

## Team

*To be filled in.*

Suggested fields per person:
- Name, role, background
- Why this person for this problem (founder–market fit)
- Equity / commitment level (full-time, part-time, advisor)

## Fundraising

*To be filled in.*

Suggested fields:
- Stage — bootstrap / pre-seed / seed
- Amount targeted — and rationale (months of runway × burn)
- Use of funds — engineering / GTM / runway split
- Existing investors — angels, accelerators (if any)
- Milestones to hit before next round — DAU, retention, paid conversion, NPS

## #1 Design Principle: Latency Is Everything

Every architectural decision must prioritize minimizing latency. Real-time voice conversation cannot tolerate delays — if the user finishes speaking and waits even a beat too long, the experience is broken. This applies to LLM inference, STT, TTS, and every layer in between.

## Tech Stack

| Layer | Choice | Package |
|---|---|---|
| Platform | Swift / SwiftUI, iOS 26+ | — |
| LLM | Qwen3.5-4B (4-bit, ~2.8GB) | `ml-explore/mlx-swift-examples` (MLXLLM) |
| STT | Apple SpeechAnalyzer | `Speech` framework (iOS 26) |
| TTS | CosyVoice3 0.5B | `Blaizzy/mlx-audio-swift` |
| VAD | Silero v5 | `helloooideeeeea/RealTimeCutVADLibrary` |
| Audio | AVAudioEngine + AVAudioPlayerNode | AVFoundation |
| Persistence | SwiftData | Built-in (iOS 17+) |
| Audio Session | `.playAndRecord`, `.voiceChat` mode | Built-in echo cancellation |

## Architecture

```
Microphone → VAD (Silero v5) → STT (SpeechAnalyzer) → LLM (Qwen3.5-4B via MLX) → TTS (CosyVoice3) → Speaker
                                                                                         ↑
                                                                              Sentence Accumulator
                                                                         (stream tokens → sentences)
```

Pipeline stages overlap: TTS speaks the first sentence while LLM generates the next.

### Voice Orchestrator States
`idle` → `listening` → `transcribing` → `thinking` → `speaking`

Barge-in: VAD detects speech during `speaking` → stop playback, cancel LLM/TTS, transition to `listening`.

## Project Structure

```
TalkingHeads/
├── TalkingHeadsApp.swift          # App entry point
├── Models/
│   ├── Conversation.swift         # SwiftData model
│   └── Message.swift              # SwiftData model
├── Audio/
│   ├── AudioPipeline.swift        # AVAudioEngine setup, mic tap, speaker output
│   └── SentenceAccumulator.swift  # Token stream → sentence chunks
├── Voice/
│   ├── VoiceOrchestrator.swift    # State machine (actor), barge-in logic
│   ├── STTService.swift           # SpeechAnalyzer wrapper
│   ├── TTSService.swift           # CosyVoice3 wrapper
│   └── VADService.swift           # Silero VAD wrapper
├── LLM/
│   ├── LLMService.swift           # MLXLLM wrapper, streaming generation
│   └── PromptBuilder.swift        # System prompts, persona templates
├── Views/
│   ├── ConversationView.swift     # Main conversation screen
│   ├── HistoryView.swift          # Past conversations
│   └── SettingsView.swift         # Persona/scenario picker
└── Resources/
    └── Personas/                  # JSON persona/scenario templates
```

## Development Notes

- Target user: Japanese English learner (founder) — UI must be in English regardless of device locale
- All inference runs on-device — zero network latency, zero API costs
- AVAudioEngine stays running at all times — never stop/start between turns
- 500ms silence threshold for turn-completion detection (tunable)
- Pre-warm LLM on app launch (dummy token to force load into memory)
