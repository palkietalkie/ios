import Foundation

/// Knowledge-graph endpoints. The graph is built by the post-session pipeline; the client reads it and can soft-delete a wrong item.
extension BackendAPI {
    func getKG() async throws -> KGGraphDTO {
        // Generous timeout: /kg reads from AuraDB, which scales to zero and can take 10-20s to wake. The screen renders the cached graph and refreshes in the background (render-then-refresh), so a slow wake just delays the refresh, it never surfaces as an error; only a decode/contract failure does.
        try await get("/kg", timeout: 60)
    }

    /// Soft-delete a wrong knowledge-graph item the user swiped away. The id is the entity name (not a UUID), so it must be path-encoded.
    func removeKGEntity(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let _: EmptyResponse = try await delete("/kg/\(encoded)")
    }
}
