import XCTest
import SwiftData
@testable import OmniChat

final class MediaItemPersistenceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Conversation.self, Message.self, StoredEndpointProfile.self, MediaItem.self, SearchPassage.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    func test_savingMessageWithMediaItem_persistsRelationshipAndFileURL() throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)

        let mediaItem = MediaItem(kind: "image", prompt: "un chat", modelID: "auto", fileName: "abc.png")
        mediaItem.conversation = conversation
        context.insert(mediaItem)

        let message = Message(role: "assistant", content: "")
        message.conversation = conversation
        message.mediaItem = mediaItem
        conversation.messages.append(message)

        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Message>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.mediaItem?.fileName, "abc.png")
        XCTAssertTrue(fetched.first?.mediaItem?.fileURL.path.hasSuffix("abc.png") ?? false)
    }
}
