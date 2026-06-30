import Foundation

/// Knowledge-graph endpoints. The graph is built by the post-session pipeline; the client reads it and can soft-delete a wrong item.
extension BackendAPI {
    func getKG() async throws -> KGGraphDTO {
        // 30s, not the default 15s: /kg reads from AuraDB, which scales to zero and can take 10-20s to wake. The KG screen shows a spinner meanwhile; failing at 15s would surface a "request timed out" to a user who actually has a graph.
        try await get("/kg", timeout: 30)
    }

    /// Soft-delete a wrong knowledge-graph item the user swiped away. The id is the entity name (not a UUID), so it must be path-encoded.
    func removeKGEntity(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let _: EmptyResponse = try await delete("/kg/\(encoded)")
    }
}
