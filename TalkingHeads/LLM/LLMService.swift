import Foundation
import MLXLLM
import MLXLMCommon

// TERMINOLOGY:
// - `MLXLLM`: Apple's MLX framework for running LLMs on Apple Silicon (M-series / A-series chips).
//   Uses the GPU's unified memory — the model weights live in shared CPU/GPU memory.
// - `ModelConfiguration`: Specifies which model to load (by Hugging Face repo ID).
// - `LLMModelFactory.shared`: Singleton factory that downloads and loads models.
//   `.shared` = singleton pattern (like a global instance).
// - `ChatSession`: Manages conversation state and KV cache (attention cache) across turns.
//   Creating a new ChatSession resets the context (forgets previous messages).
// - `streamResponse(to:)`: Returns an AsyncThrowingStream — you `for try await` over it
//   to get tokens one by one as they're generated (like SSE/streaming in web APIs).
// - `AsyncThrowingStream`: Like AsyncStream but can also throw errors mid-stream.

/// Wraps MLXLLM for on-device streaming text generation.
actor LLMService {
    private var session: ChatSession?
    private var modelContainer: ModelContainer?

    private let modelID = "mlx-community/Qwen3-4B-4bit"

    /// Load the model and pre-warm with a dummy generation.
    func warmUp() async throws {
        let config = ModelConfiguration(id: modelID)
        let container = try await LLMModelFactory.shared.loadContainer(
            configuration: config
        ) { progress in
            print("[LLM] Download progress: \(progress.fractionCompleted)")
        }
        modelContainer = container
        session = ChatSession(container)

        // Pre-warm: force load weights into memory
        _ = try await session?.respond(to: "Hi")
        // Reset so the warmup exchange isn't in context
        session = ChatSession(container)
    }

    /// Stream a response token-by-token given a user message.
    /// The system prompt should already be set via `setSystemPrompt`.
    func streamResponse(to message: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let session = self.session else {
                    continuation.finish(throwing: LLMError.modelNotLoaded)
                    return
                }
                do {
                    for try await chunk in session.streamResponse(to: message) {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Reset the conversation context (new conversation).
    func resetContext() {
        guard let container = modelContainer else { return }
        session = ChatSession(container)
    }

    /// Rebuild the session with a system prompt and conversation history.
    func configure(systemPrompt: String, history: [(role: String, content: String)]) async throws {
        guard let container = modelContainer else {
            throw LLMError.modelNotLoaded
        }
        session = ChatSession(container, systemPrompt: systemPrompt, history: history)
    }
}

enum LLMError: Error {
    case modelNotLoaded
}
