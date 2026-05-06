import Foundation

/// Wraps MLXLLM for on-device streaming text generation.
/// TODO: implement; previous code hit MLXLLM overload-resolution issues
/// against current package version (loadContainer ambiguity vs.
/// GenericModelFactory.loadContainer(from:using:...)).
actor LLMService {
    func warmUp() async throws {
        // TODO: load Qwen3 via LLMModelFactory.shared.loadContainer.
    }

    func streamResponse(to message: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: LLMError.notImplemented)
        }
    }

    func resetContext() {
        // TODO: rebuild ChatSession.
    }

    func configure(systemPrompt: String, history: [(role: String, content: String)]) async throws {
        // TODO: rebuild ChatSession with instructions and Chat.Message history.
    }
}

enum LLMError: Error {
    case modelNotLoaded
    case notImplemented
}
