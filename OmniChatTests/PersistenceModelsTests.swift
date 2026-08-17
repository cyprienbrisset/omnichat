import XCTest
import SwiftData
@testable import OmniChat

final class PersistenceModelsTests: XCTestCase {
    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([Conversation.self, Message.self, StoredEndpointProfile.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    func test_savingConversationWithMessage_persistsRelationship() throws {
        let context = try makeInMemoryContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        let message = Message(role: "user", content: "Salut")
        message.conversation = conversation
        conversation.messages.append(message)
        context.insert(conversation)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Conversation>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.messages.count, 1)
        XCTAssertEqual(fetched.first?.messages.first?.content, "Salut")
    }
}
