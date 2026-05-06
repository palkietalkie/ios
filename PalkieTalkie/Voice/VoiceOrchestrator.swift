import AVFoundation
import Foundation
import SwiftData

// TERMINOLOGY:
// - `actor`: Like a class but with built-in thread safety. Only one piece of code
//   can access an actor's state at a time (similar to a mutex/lock in other languages).
//   In TS terms: imagine every method is automatically queued so no race conditions.
// - `@Published`: Makes a property observable — SwiftUI views automatically re-render
//   when this changes (like React state / MobX observable).
// - `@MainActor`: Forces code to run on the main thread (UI thread).
//   Similar to how React state updates must happen on the main thread.
// - `Task`: Swift's equivalent of a Promise. `Task { }` is like `new Promise(async () => { })`.
//   You can cancel a Task (unlike most JS promises).
// - `AsyncStream`: Like an async generator/iterator in JS/Python.

/// The voice conversation state machine.
/// Coordinates: VAD → STT → LLM → TTS → Speaker
///
/// States flow: idle → listening → transcribing → thinking → speaking → listening → ...
/// "Barge-in" = user starts talking while the AI is speaking → immediately stop and listen.
@MainActor
final class VoiceOrchestrator: ObservableObject {
    // `@Published` = observable state. SwiftUI views re-render when these change.
    @Published var state: VoiceState = .idle
    @Published var lastTranscript: String = ""
    @Published var lastResponse: String = ""

    // Dependencies (like constructor injection in TS/Angular)
    private let audioPipeline = AudioPipeline()
    private let vadService = VADService()
    private let sttService = STTService()
    private let llmService = LLMService()
    private let ttsService = TTSService()
    private let sentenceAccumulator = SentenceAccumulator()

    // `Task?` = a cancellable async operation (like AbortController + fetch in JS)
    private var llmTask: Task<Void, Never>?
    private var ttsTask: Task<Void, Never>?

    // SwiftData context for persisting messages (like a DB connection/ORM session)
    private var modelContext: ModelContext?
    private var currentConversation: Conversation?

    // Settings
    var selectedPersona: Persona?
    var selectedScenario: Scenario?

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Lifecycle

    /// Call once on app launch. Downloads models and warms up LLM.
    func prepare() async {
        do {
            // Download STT model, load LLM and TTS into memory — all in parallel
            // `async let` = like Promise.all() — runs concurrently
            async let sttPrep: () = sttService.prepareModel()
            async let llmPrep: () = llmService.warmUp()
            async let ttsPrep: () = ttsService.warmUp()
            try await sttPrep
            try await llmPrep
            try await ttsPrep
            print("[Orchestrator] All models ready")
        } catch {
            print("[Orchestrator] Model preparation failed: \(error)")
        }
    }

    /// Start listening for voice input.
    func startConversation() {
        guard state == .idle else { return }

        // Create a new conversation record in the database
        let conversation = Conversation(
            title: "Conversation",
            personaID: selectedPersona?.id
        )
        modelContext?.insert(conversation)
        currentConversation = conversation

        setupCallbacks()

        do {
            try audioPipeline.start()
            state = .listening
        } catch {
            print("[Orchestrator] Failed to start audio: \(error)")
        }
    }

    func stopConversation() {
        cancelInFlight()
        audioPipeline.stop()
        state = .idle
        currentConversation = nil
    }

    // MARK: - Barge-in

    /// User started talking while AI is speaking → stop everything and listen.
    private func handleBargeIn() {
        guard state == .speaking else { return }

        audioPipeline.stopPlayback()
        // `.cancel()` is like AbortController.abort() — stops the async operation
        llmTask?.cancel()
        ttsTask?.cancel()
        Task { await sentenceAccumulator.reset() }
        state = .listening
    }

    // MARK: - Pipeline

    private func setupCallbacks() {
        // Wire mic audio → VAD (voice activity detection)
        // This closure is called ~30x/sec with small audio chunks from the microphone
        audioPipeline.onAudioBuffer = { [weak self] buffer in
            // `[weak self]` prevents memory leaks (like weak references in other languages).
            // Without it, this closure would keep `self` alive forever.
            self?.vadService.process(buffer)
        }

        // VAD detected voice started
        vadService.onVoiceStarted = { [weak self] in
            Task { @MainActor in
                self?.handleBargeIn()
            }
        }

        // VAD detected voice ended → transcribe
        // `audioData` is the recorded speech as WAV bytes
        vadService.onVoiceEnded = { [weak self] audioData in
            Task { @MainActor in
                await self?.handleVoiceEnded(audioData)
            }
        }
    }

    private func handleVoiceEnded(_ audioData: Data) async {
        state = .transcribing

        do {
            let transcript = try await sttService.transcribe(audioData)
            guard !transcript.trimmingCharacters(in: .whitespaces).isEmpty else {
                state = .listening
                return
            }

            lastTranscript = transcript
            saveMessage(role: .user, content: transcript)
            await generateResponse(to: transcript)
        } catch {
            print("[Orchestrator] STT failed: \(error)")
            state = .listening
        }
    }

    private func generateResponse(to userMessage: String) async {
        state = .thinking

        // Build conversation context from stored messages
        let history = currentConversation.map {
            PromptBuilder.buildHistory(from: $0.sortedMessages)
        } ?? []
        let systemPrompt = PromptBuilder.buildSystemPrompt(
            persona: selectedPersona,
            scenario: selectedScenario
        )

        do {
            try await llmService.configure(systemPrompt: systemPrompt, history: history)
        } catch {
            print("[Orchestrator] LLM configure failed: \(error)")
            state = .listening
            return
        }

        state = .speaking
        lastResponse = ""

        // Get sentence stream from accumulator
        let sentences = await sentenceAccumulator.sentences()

        // Start LLM streaming — feed tokens into the sentence accumulator
        // `Task { }` launches concurrent work (like spawning a goroutine or starting a Promise)
        llmTask = Task {
            do {
                let stream = await llmService.streamResponse(to: userMessage)
                for try await token in stream {
                    guard !Task.isCancelled else { return }
                    lastResponse += token
                    await sentenceAccumulator.addToken(token)
                }
                await sentenceAccumulator.flush()
            } catch {
                if !Task.isCancelled {
                    print("[Orchestrator] LLM generation failed: \(error)")
                }
                await sentenceAccumulator.flush()
            }
        }

        // Consume sentences and speak them via TTS
        // This runs concurrently with LLM generation — speaks sentence 1 while generating sentence 2
        ttsTask = Task {
            for await sentence in sentences {
                guard !Task.isCancelled else { return }
                do {
                    let audioBuffer = try await ttsService.synthesize(sentence)
                    guard !Task.isCancelled else { return }
                    audioPipeline.scheduleBuffer(audioBuffer)
                } catch {
                    if !Task.isCancelled {
                        print("[Orchestrator] TTS failed: \(error)")
                    }
                }
            }

            // All sentences spoken — save full response and go back to listening
            if !Task.isCancelled {
                await MainActor.run {
                    self.saveMessage(role: .assistant, content: self.lastResponse)
                    self.state = .listening
                }
            }
        }
    }

    // MARK: - Persistence

    private func saveMessage(role: MessageRole, content: String) {
        guard let conversation = currentConversation else { return }
        let message = Message(role: role, content: content)
        message.conversation = conversation
        conversation.updatedAt = Date()
        modelContext?.insert(message)
        // `try?` = "try and ignore errors" (like a try/catch that swallows the exception)
        try? modelContext?.save()
    }

    private func cancelInFlight() {
        llmTask?.cancel()
        ttsTask?.cancel()
        audioPipeline.stopPlayback()
        Task { await sentenceAccumulator.reset() }
    }
}

// `enum` = like TypeScript union types: type VoiceState = "idle" | "listening" | ...
enum VoiceState: String {
    case idle
    case listening
    case transcribing
    case thinking
    case speaking
}
