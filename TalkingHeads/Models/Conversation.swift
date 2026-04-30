import Foundation
import SwiftData

// TERMINOLOGY:
// - `@Model`: SwiftData macro that makes this class a database table (like a Prisma/Sequelize model).
//   SwiftData is Apple's ORM — it auto-generates SQLite schema from your class properties.
// - `final class`: A class that can't be subclassed (like `sealed` in Kotlin).
// - `UUID`: Universally unique ID (like crypto.randomUUID() in JS).
// - `String?`: The `?` means optional/nullable (like `string | null` in TS).
// - `@Relationship`: Defines a foreign key relationship between tables.
//   `deleteRule: .cascade` = deleting a Conversation also deletes its Messages (like ON DELETE CASCADE in SQL).
//   `inverse: \Message.conversation` = tells SwiftData the back-reference field on Message.

@Model
final class Conversation {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var personaID: String?

    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message]

    init(title: String = "", personaID: String? = nil) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.personaID = personaID
        self.messages = []
    }

    var sortedMessages: [Message] {
        messages.sorted { $0.timestamp < $1.timestamp }
    }
}
