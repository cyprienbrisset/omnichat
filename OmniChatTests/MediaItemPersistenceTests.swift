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

    /// Regression test for a real, confirmed bug: without an explicit
    /// `@Relationship(inverse:)` pairing `Message.mediaItem` with
    /// `MediaItem.message` (and `Conversation.mediaItems` with
    /// `MediaItem.conversation`), two successive successful media
    /// generations in the same conversation ended up sharing a single
    /// persisted `MediaItem` row — confirmed live via the real SwiftData
    /// store: two real files on disk, but only one `MediaItem` row,
    /// referenced by both messages (the second generation's data silently
    /// overwrote the first's).
    func test_twoMediaItemsInSameConversation_persistAsIndependentRows() throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)

        let firstMedia = MediaItem(kind: "image", prompt: "un chat", modelID: "auto", fileName: "first.png")
        firstMedia.conversation = conversation
        context.insert(firstMedia)
        let firstMessage = Message(role: "assistant", content: "")
        firstMessage.conversation = conversation
        firstMessage.mediaItem = firstMedia
        conversation.messages.append(firstMessage)
        try context.save()

        let secondMedia = MediaItem(kind: "image", prompt: "un chat sur la lune", modelID: "auto", fileName: "second.png")
        secondMedia.conversation = conversation
        context.insert(secondMedia)
        let secondMessage = Message(role: "assistant", content: "")
        secondMessage.conversation = conversation
        secondMessage.mediaItem = secondMedia
        conversation.messages.append(secondMessage)
        try context.save()

        let allMediaItems = try context.fetch(FetchDescriptor<MediaItem>())
        XCTAssertEqual(allMediaItems.count, 2, "each generation must persist its own MediaItem row")
        XCTAssertEqual(Set(allMediaItems.map(\.fileName)), ["first.png", "second.png"])

        let messages = try context.fetch(FetchDescriptor<Message>(sortBy: [SortDescriptor(\.createdAt)]))
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].mediaItem?.fileName, "first.png", "the first message must still point at its own media, not the second's")
        XCTAssertEqual(messages[1].mediaItem?.fileName, "second.png")
    }
}
