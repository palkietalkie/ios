import Foundation
import SwiftData

// TERMINOLOGY:
// - `enum`: Like TypeScript union types. `MessageRole` = "system" | "user" | "assistant".
//   `: String` means each case has a raw string value (like string enums in TS).
// - `Codable`: Protocol that enables JSON serialization/deserialization
//   (like implementing toJSON/fromJSON, or using Pydantic in Python).

enum MessageRole: String, Codable {
    case system
    case user
    case assistant
}

@Model
final class Message {
    var id: UUID
    var role: MessageRole
    var content: String
    var timestamp: Date
    var conversation: Conversation?

    init(role: MessageRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}
