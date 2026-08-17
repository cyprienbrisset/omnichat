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
}
