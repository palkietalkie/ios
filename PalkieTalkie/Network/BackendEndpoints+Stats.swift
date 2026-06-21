import Foundation

/// Speaking analytics: aggregate stats plus the drill-down lists (mistakes, frequent phrases, CEFR coverage).
extension BackendAPI {
    func getStats() async throws -> Stats {
        try await get("/stats")
    }

    func getMistakes() async throws -> [Mistake] {
        try await get("/stats/mistakes")
    }

    func getPhrases() async throws -> [PhraseUsage] {
        try await get("/stats/phrases")
    }

    func getCEFRWords(level: String) async throws -> [CEFRWord] {
        try await get("/stats/cefr?level=\(level)")
    }
}
