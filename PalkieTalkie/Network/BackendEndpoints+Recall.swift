import Foundation

/// Conversation-time recall, invoked when the realtime model calls a tool. Each returns concise text for the model to read back.
extension BackendAPI {
    private func encodeQuery(_ q: String) -> String {
        q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
    }

    func recallFacts(query: String) async throws -> String {
        let dto: RecallFactsDTO = try await get("/recall/facts?q=\(encodeQuery(query))")
        guard !dto.entities.isEmpty else { return "No matching facts found." }
        return dto.entities.map { entity in
            let rels = entity.relations
                .map { "\($0.rel ?? "related to") \($0.target)" }
                .joined(separator: "; ")
            return rels.isEmpty ? "\(entity.name) (\(entity.type))" : "\(entity.name) (\(entity.type)): \(rels)"
        }.joined(separator: "\n")
    }

    func recallConversations(query: String) async throws -> String {
        let dto: RecallConversationsDTO = try await get("/recall/conversations?q=\(encodeQuery(query))")
        return dto.snippets.isEmpty ? "No relevant past conversations." : dto.snippets.joined(separator: "\n")
    }

    func searchTranscripts(query: String) async throws -> String {
        let dto: RecallTranscriptsDTO = try await get("/recall/transcripts?q=\(encodeQuery(query))")
        guard !dto.turns.isEmpty else { return "No matching past words found." }
        return dto.turns.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
    }

    func webFetch(url: String) async throws -> String {
        let dto: WebFetchDTO = try await get("/recall/web_fetch?url=\(encodeQuery(url))")
        return dto.content.isEmpty ? "Couldn't read that page." : dto.content
    }
}
