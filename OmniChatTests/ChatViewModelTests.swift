import XCTest
import SwiftData
@testable import OmniChat
import OmniRouteKit

private final class FakeChatCompleting: ChatCompleting, @unchecked Sendable {
    let deltas: [ChatDelta]
    let error: OmniRouteError?
    private(set) var capturedRequests: [ChatCompletionRequest] = []

    init(deltas: [ChatDelta], error: OmniRouteError?) {
        self.deltas = deltas
        self.error = error
    }

    var lastRequest: ChatCompletionRequest? { capturedRequests.last }

    func streamChatCompletion(_ request: ChatCompletionRequest) -> AsyncThrowingStream<ChatDelta, Error> {
        capturedRequests.append(request)
        return AsyncThrowingStream { continuation in
            for delta in deltas { continuation.yield(delta) }
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }
}

@MainActor
final class ChatViewModelTests: XCTestCase {
    private func makeSchema() -> Schema {
        Schema([Conversation.self, Message.self, StoredEndpointProfile.self])
    }

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(schema: makeSchema(), isStoredInMemoryOnly: true)
        return try ModelContainer(for: makeSchema(), configurations: [config])
    }

    private func makeContext() throws -> ModelContext {
        ModelContext(try makeContainer())
    }

    private func makeDiagnosticLogger() -> DiagnosticLogger {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnichat-tests-\(UUID().uuidString).json")
        return DiagnosticLogger(fileURL: url)
    }

    private func makeViewModel(conversation: Conversation, client: ChatCompleting, context: ModelContext) -> ChatViewModel {
        ChatViewModel(
            conversation: conversation,
            client: client,
            context: context,
            diagnosticLogger: makeDiagnosticLogger(),
            endpointName: "Test"
        )
    }

    func test_send_appendsUserAndAssembledAssistantMessage() async throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)
        let fake = FakeChatCompleting(
            deltas: [ChatDelta(content: "Bon", isFinal: false), ChatDelta(content: "jour", isFinal: false)],
            error: nil
        )
        let viewModel = makeViewModel(conversation: conversation, client: fake, context: context)

        await viewModel.send("Salut")

        XCTAssertEqual(conversation.messages.count, 2)
        XCTAssertEqual(conversation.orderedMessages.last?.content, "Bonjour")
        XCTAssertNil(viewModel.currentError)
    }

    func test_send_onError_marksAssistantMessageIncompleteAndExposesError() async throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)
        let fake = FakeChatCompleting(
            deltas: [ChatDelta(content: "Bon", isFinal: false)],
            error: .network(description: "timeout")
        )
        let viewModel = makeViewModel(conversation: conversation, client: fake, context: context)

        await viewModel.send("Salut")

        XCTAssertEqual(viewModel.currentError, .network(description: "timeout"))
        XCTAssertEqual(conversation.orderedMessages.last?.isIncomplete, true)
    }

    /// Regression test for the ordering bug: `conversation.messages` is backed
    /// by an unordered SwiftData relationship. This simulates that by
    /// appending pre-existing messages in a deliberately non-chronological
    /// order and asserts that the request sent to the model is nonetheless in
    /// `createdAt` order, and excludes the empty assistant placeholder.
    func test_send_buildsHistoryInChronologicalOrder_regardlessOfAppendOrder() async throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)

        let base = Date(timeIntervalSince1970: 1_000_000)
        let first = Message(role: "user", content: "premier", createdAt: base)
        let second = Message(role: "assistant", content: "deuxieme", createdAt: base.addingTimeInterval(10))
        let third = Message(role: "user", content: "troisieme", createdAt: base.addingTimeInterval(20))

        // Append in non-chronological order to simulate an unordered relationship.
        third.conversation = conversation
        conversation.messages.append(third)
        first.conversation = conversation
        conversation.messages.append(first)
        second.conversation = conversation
        conversation.messages.append(second)

        let fake = FakeChatCompleting(
            deltas: [ChatDelta(content: "reponse", isFinal: false)],
            error: nil
        )
        let viewModel = makeViewModel(conversation: conversation, client: fake, context: context)

        await viewModel.send("quatrieme")

        guard let request = fake.lastRequest else {
            XCTFail("expected a captured request")
            return
        }

        XCTAssertEqual(
            request.messages.map(\.content),
            ["premier", "deuxieme", "troisieme", "quatrieme"]
        )
        XCTAssertFalse(request.messages.contains { $0.content.isEmpty })
    }

    /// This is the test that should have existed after the original ordering
    /// bug diagnosis: fetch the conversation from a FRESH ModelContext (not
    /// the one used to write it) and confirm `orderedMessages` is
    /// chronological even though the underlying relationship is unordered.
    func test_orderedMessages_isChronological_afterFreshFetch() throws {
        let container = try makeContainer()
        let writeContext = ModelContext(container)

        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        writeContext.insert(conversation)

        let base = Date(timeIntervalSince1970: 2_000_000)
        let messages = [
            Message(role: "user", content: "un", createdAt: base.addingTimeInterval(30)),
            Message(role: "assistant", content: "deux", createdAt: base),
            Message(role: "user", content: "trois", createdAt: base.addingTimeInterval(15))
        ]
        for message in messages {
            message.conversation = conversation
            conversation.messages.append(message)
        }
        try writeContext.save()

        let conversationID = conversation.persistentModelID
        let readContext = ModelContext(container)
        let fetched = try XCTUnwrap(
            try readContext.fetch(FetchDescriptor<Conversation>())
                .first { $0.persistentModelID == conversationID }
        )

        XCTAssertEqual(fetched.orderedMessages.map(\.content), ["deux", "trois", "un"])
    }
}
