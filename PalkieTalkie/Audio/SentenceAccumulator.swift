import Foundation

// TERMINOLOGY:
// - `actor`: Thread-safe class. Only one caller can access its state at a time.
//   Think of it as a class where every method automatically acquires a lock.
//   You must `await` when calling actor methods from outside (like async functions).
// - `AsyncStream`: An async iterable (like async generators in JS/Python).
//   `yield` pushes values, `finish` ends the stream.
// - `continuation`: The "write end" of an AsyncStream — you yield values through it.
//   The "read end" is what you `for await` over.
// - `CharacterSet`: A set of Unicode characters to match against (like a regex character class).

/// Collects streaming LLM tokens and emits complete sentences for TTS.
/// Splits on sentence-ending punctuation: . ? ! ;
actor SentenceAccumulator {
    private var buffer = ""
    private var continuation: AsyncStream<String>.Continuation?

    private static let sentenceEndings: CharacterSet = CharacterSet(charactersIn: ".?!;")

    /// Returns an AsyncStream of complete sentences.
    /// Feed tokens via `addToken(_:)`, call `flush()` when generation ends.
    func sentences() -> AsyncStream<String> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func addToken(_ token: String) {
        buffer += token

        while let range = buffer.rangeOfCharacter(from: Self.sentenceEndings) {
            let endIndex = buffer.index(after: range.lowerBound)
            let sentence = String(buffer[buffer.startIndex..<endIndex]).trimmingCharacters(in: .whitespaces)
            buffer = String(buffer[endIndex...])

            if !sentence.isEmpty {
                continuation?.yield(sentence)
            }
        }
    }

    /// Emit any remaining text as a final sentence.
    func flush() {
        let remaining = buffer.trimmingCharacters(in: .whitespaces)
        if !remaining.isEmpty {
            continuation?.yield(remaining)
        }
        buffer = ""
        continuation?.finish()
        continuation = nil
    }

    func reset() {
        buffer = ""
        continuation?.finish()
        continuation = nil
    }
}
