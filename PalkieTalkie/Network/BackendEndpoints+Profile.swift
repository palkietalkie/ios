import Foundation

/// User profile + account lifecycle, and the server-owned option lists the profile editor renders.
extension BackendAPI {
    func getProfile() async throws -> ProfileDTO {
        try await get("/profile")
    }

    func updateProfile(_ update: ProfileUpdate) async throws -> ProfileDTO {
        try await patch("/profile", body: update)
    }

    func getPracticeOptions() async throws -> PracticeOptionsDTO {
        try await get("/profile/practice-options")
    }

    /// Soft-delete the signed-in account. Backend stamps deleted_at and rejects all further requests for this user; the caller signs out afterward. Counts are preserved server-side (the row is retained).
    func deleteAccount() async throws {
        let _: EmptyResponse = try await delete("/account")
    }
}
