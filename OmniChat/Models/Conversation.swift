import Foundation
import SwiftData

@Model
final class Conversation {
    var title: String
    var createdAt: Date
    var defaultModelID: String
    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message] = []

    init(title: String, defaultModelID: String, createdAt: Date = Date()) {
        self.title = title
        self.defaultModelID = defaultModelID
        self.createdAt = createdAt
    }

    /// SwiftData's to-many relationships are backed by an unordered store, so
    /// `messages` itself must never be relied on for chronological order.
    /// This is the single source of truth for message ordering across the app.
    var orderedMessages: [Message] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }
}
