import XCTest
import SwiftData
@testable import OmniChat
import OmniRouteKit

private struct FakeChatCompleting: ChatCompleting {
    let deltas: [ChatDelta]
    let error: OmniRouteError?

    func streamChatCompletion(_ request: ChatCompletionRequest) -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
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
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Conversation.self, Message.self, StoredEndpointProfile.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    func test_send_appendsUserAndAssembledAssistantMessage() async throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)
        let fake = FakeChatCompleting(
            deltas: [ChatDelta(content: "Bon", isFinal: false), ChatDelta(content: "jour", isFinal: false)],
            error: nil
        )
        let viewModel = ChatViewModel(conversation: conversation, client: fake, context: context)

        await viewModel.send("Salut")

        XCTAssertEqual(conversation.messages.count, 2)
        XCTAssertEqual(conversation.messages.last?.content, "Bonjour")
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
        let viewModel = ChatViewModel(conversation: conversation, client: fake, context: context)

        await viewModel.send("Salut")

        XCTAssertEqual(viewModel.currentError, .network(description: "timeout"))
        XCTAssertEqual(conversation.messages.last?.isIncomplete, true)
    }
}
