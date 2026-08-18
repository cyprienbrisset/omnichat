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

/// Yields deltas with a small delay between each, giving tests a real window
/// to cancel the wrapping `Task` mid-stream (unlike `FakeChatCompleting`,
/// which yields its whole array synchronously with no cancellation window).
private final class SlowFakeChatCompleting: ChatCompleting, @unchecked Sendable {
    func streamChatCompletion(_ request: ChatCompletionRequest) -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                for chunk in ["Un", "Deux", "Trois", "Quatre", "Cinq"] {
                    try? await Task.sleep(for: .milliseconds(30))
                    continuation.yield(ChatDelta(content: chunk, isFinal: false))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private final class FakeMediaGenerating: MediaGenerating, @unchecked Sendable {
    enum Outcome {
        case success(MediaGenerationResult)
        case failure(Error)
    }

    var outcome: Outcome = .success(.inlineData(Data("fake".utf8), contentType: "image/png"))
    private(set) var lastPrompt: String?

    private func resolve(_ prompt: String) throws -> MediaGenerationResult {
        lastPrompt = prompt
        switch outcome {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }

    func generateImage(_ request: MediaGenerationRequest) async throws -> MediaGenerationResult {
        try resolve(request.prompt)
    }
    func generateVideo(_ request: MediaGenerationRequest) async throws -> MediaGenerationResult {
        try resolve(request.prompt)
    }
    func generateMusic(_ request: MediaGenerationRequest) async throws -> MediaGenerationResult {
        try resolve(request.prompt)
    }
    func synthesizeSpeech(_ request: SpeechRequest) async throws -> MediaGenerationResult {
        try resolve(request.input)
    }
}

@MainActor
final class ChatViewModelTests: XCTestCase {
    private func makeSchema() -> Schema {
        Schema([Conversation.self, Message.self, StoredEndpointProfile.self, MediaItem.self])
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

    private func makeMediaFileStore() -> MediaFileStore {
        MediaFileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    private func makeViewModel(
        conversation: Conversation,
        client: ChatCompleting,
        context: ModelContext,
        mediaClient: MediaGenerating = FakeMediaGenerating()
    ) -> ChatViewModel {
        ChatViewModel(
            conversation: conversation,
            client: client,
            mediaClient: mediaClient,
            mediaFileStore: makeMediaFileStore(),
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

    func test_send_appliesTelemetryFromDeltaToAssistantMessage() async throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)
        let telemetry = RequestTelemetry(
            routingStrategy: "cheapest",
            routingProvider: "cerebras",
            routingLatencyMs: 812,
            responseCostUSD: 0.0012,
            tokensIn: 128,
            tokensOut: 342,
            cacheHit: false
        )
        let fake = FakeChatCompleting(
            deltas: [
                ChatDelta(content: "", isFinal: false, telemetry: telemetry),
                ChatDelta(content: "Bonjour", isFinal: false)
            ],
            error: nil
        )
        let viewModel = makeViewModel(conversation: conversation, client: fake, context: context)

        await viewModel.send("Salut")

        let assistantMessage = try XCTUnwrap(conversation.orderedMessages.last { $0.role == "assistant" })
        XCTAssertEqual(assistantMessage.routingProvider, "cerebras")
        XCTAssertEqual(assistantMessage.routingLatencyMs, 812)
        XCTAssertEqual(assistantMessage.tokensOut, 342)
        XCTAssertEqual(assistantMessage.telemetrySummary, "cheapest → cerebras · 812 ms · $0.0012 · 128→342 tok")
    }

    func test_send_whenWrappingTaskCancelled_marksAssistantMessageIncompleteWithoutError() async throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)
        let fake = SlowFakeChatCompleting()
        let viewModel = makeViewModel(conversation: conversation, client: fake, context: context)

        let task = Task { await viewModel.send("Salut") }
        try await Task.sleep(for: .milliseconds(45))
        task.cancel()
        await task.value

        XCTAssertNil(viewModel.currentError)
        XCTAssertEqual(conversation.orderedMessages.last?.role, "assistant")
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

    func test_sendMediaPrompt_createsMediaItemAndLinksToAssistantMessage() async throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)
        let fakeChat = FakeChatCompleting(deltas: [], error: nil)
        let fakeMedia = FakeMediaGenerating()
        let viewModel = makeViewModel(conversation: conversation, client: fakeChat, context: context, mediaClient: fakeMedia)

        await viewModel.sendMediaPrompt("un chat sur la lune", kind: .image)

        XCTAssertEqual(fakeMedia.lastPrompt, "un chat sur la lune")
        let assistantMessage = conversation.orderedMessages.last
        XCTAssertEqual(assistantMessage?.mediaItem?.kind, "image")
        XCTAssertNil(viewModel.currentError)
    }

    func test_retryLastMessage_afterFailedMediaPrompt_retriesSameKind() async throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)
        let fakeChat = FakeChatCompleting(deltas: [], error: nil)
        let fakeMedia = FakeMediaGenerating()
        fakeMedia.outcome = .failure(OmniRouteError.network(description: "timeout"))
        let viewModel = makeViewModel(conversation: conversation, client: fakeChat, context: context, mediaClient: fakeMedia)

        await viewModel.sendMediaPrompt("un chat", kind: .image)
        XCTAssertNotNil(viewModel.currentError)

        fakeMedia.outcome = .success(.inlineData(Data("fake".utf8), contentType: "image/png"))
        await viewModel.retryLastMessage()

        XCTAssertNil(viewModel.currentError)
        XCTAssertEqual(conversation.orderedMessages.last?.mediaItem?.kind, "image")
    }
}
