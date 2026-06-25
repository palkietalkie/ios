import Foundation

/// In-app "rate your experience" submission. POSTs to `/ratings`, its own typed table in Neon (not the events sink), and the backend pings Slack server-side. Fire-and-forget: a failed report must never disrupt the conversation.
extension BackendAPI {
    func recordExperienceRating(rating: Int, comment: String?) async throws {
        struct Body: Codable {
            let rating: Int
            let comment: String?
        }
        let _: EmptyResponse = try await post(
            "/ratings",
            body: Body(rating: rating, comment: comment.map { String($0.prefix(1000)) }),
        )
    }
}
