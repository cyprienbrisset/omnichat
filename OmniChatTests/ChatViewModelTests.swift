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

/// Returns a different delta sequence on each successive call — needed to
/// test a tool-calling round-trip, where the same `ChatViewModel.send()`
/// issues a first request (ending in a tool call) and a follow-up request
/// (with the tool's result folded into history) that must yield different
/// content.
private final class SequencedFakeChatCompleting: ChatCompleting, @unchecked Sendable {
    private var remainingRounds: [[ChatDelta]]
    private(set) var capturedRequests: [ChatCompletionRequest] = []

    init(rounds: [[ChatDelta]]) {
        self.remainingRounds = rounds
    }

    func streamChatCompletion(_ request: ChatCompletionRequest) -> AsyncThrowingStream<ChatDelta, Error> {
        capturedRequests.append(request)
        let deltas = remainingRounds.isEmpty ? [] : remainingRounds.removeFirst()
        return AsyncThrowingStream { continuation in
            for delta in deltas { continuation.yield(delta) }
            continuation.finish()
        }
    }
}

private struct FakeCalculatorTool: LocalTool {
    var definition: ToolDefinition {
        ToolDefinition(function: .init(
            name: "calculator",
            description: "test tool",
            parameters: ToolParameterSchema(properties: ["expression": .init(type: "string", description: "expr")], required: ["expression"])
        ))
    }

    func execute(argumentsJSON: String) async throws -> String {
        "4183"
    }
}

private final class FakeMediaGenerating: MediaGenerating, @unchecked Sendable {
    enum Outcome {
        case success(MediaGenerationResult)
        case failure(Error)
    }

    var outcome: Outcome = .success(.inlineData(Data("fake".utf8), contentType: "image/png"))
    /// Per-model override, checked before the blanket `outcome` — lets a
    /// test simulate one catalog entry 404ing and a later one succeeding.
    var outcomesByModel: [String: Outcome] = [:]
    var catalog = [ModelInfo(id: "fake/model", ownedBy: "fake")]
    private(set) var lastPrompt: String?
    private(set) var attemptedModelIDs: [String] = []

    private func resolve(_ prompt: String, modelID: String) throws -> MediaGenerationResult {
        lastPrompt = prompt
        attemptedModelIDs.append(modelID)
        switch outcomesByModel[modelID] ?? outcome {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }

    func generateImage(_ request: MediaGenerationRequest) async throws -> MediaGenerationResult {
        try resolve(request.prompt, modelID: request.model)
    }
    func generateVideo(_ request: MediaGenerationRequest) async throws -> MediaGenerationResult {
        try resolve(request.prompt, modelID: request.model)
    }
    func generateMusic(_ request: MediaGenerationRequest) async throws -> MediaGenerationResult {
        try resolve(request.prompt, modelID: request.model)
    }
    func synthesizeSpeech(_ request: SpeechRequest) async throws -> MediaGenerationResult {
        try resolve(request.input, modelID: request.model)
    }

    func listImageModels() async throws -> [ModelInfo] { catalog }
    func listVideoModels() async throws -> [ModelInfo] { catalog }
    func listMusicModels() async throws -> [ModelInfo] { catalog }
    func listSpeechModels() async throws -> [ModelInfo] { catalog }
}

private final class FakeAudioTranscribing: AudioTranscribing, @unchecked Sendable {
    var catalog = [ModelInfo(id: "fake/transcriber", ownedBy: "fake")]
    var outcomesByModel: [String: Result<TranscriptionResult, Error>] = [:]
    private(set) var attemptedModelIDs: [String] = []

    func listTranscriptionModels() async throws -> [ModelInfo] { catalog }

    func transcribeAudio(fileData: Data, fileName: String, model: String) async throws -> TranscriptionResult {
        attemptedModelIDs.append(model)
        guard let outcome = outcomesByModel[model] else {
            return TranscriptionResult(text: "fake transcript")
        }
        switch outcome {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }
}

@MainActor
final class ChatViewModelTests: XCTestCase {
    private func makeSchema() -> Schema {
        Schema([Conversation.self, Message.self, StoredEndpointProfile.self, MediaItem.self, SearchPassage.self])
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
        mediaClient: MediaGenerating = FakeMediaGenerating(),
        transcriptionClient: AudioTranscribing = FakeAudioTranscribing(),
        localTools: [LocalTool] = []
    ) -> ChatViewModel {
        ChatViewModel(
            conversation: conversation,
            client: client,
            mediaClient: mediaClient,
            transcriptionClient: transcriptionClient,
            mediaFileStore: makeMediaFileStore(),
            context: context,
            diagnosticLogger: makeDiagnosticLogger(),
            endpointName: "Test",
            localTools: localTools
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

    func test_send_toolCall_executesLocalToolAndContinuesWithResult() async throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)
        let fake = SequencedFakeChatCompleting(rounds: [
            [
                ChatDelta(
                    content: "",
                    isFinal: false,
                    toolCallDeltas: [ToolCallDelta(index: 0, id: "call_1", name: "calculator", argumentsFragment: "{\"expression\":\"47*89\"}")]
                ),
                ChatDelta(content: "", isFinal: false, finishReason: "tool_calls"),
            ],
            [ChatDelta(content: "47 × 89 = 4183", isFinal: false)],
        ])
        let viewModel = makeViewModel(conversation: conversation, client: fake, context: context, localTools: [FakeCalculatorTool()])

        await viewModel.send("Combien font 47 fois 89 ?")

        XCTAssertEqual(fake.capturedRequests.count, 2)
        XCTAssertEqual(conversation.orderedMessages.last?.content, "47 × 89 = 4183")
        XCTAssertEqual(conversation.orderedMessages.last?.toolName, "calculator")
        XCTAssertEqual(conversation.orderedMessages.last?.toolResult, "4183")
        // The follow-up request must carry the assistant's tool call and the
        // tool's real result so the model can see what it asked for and got.
        let secondRequestMessages = fake.capturedRequests[1].messages
        XCTAssertEqual(secondRequestMessages.last?.role, .tool)
        XCTAssertEqual(secondRequestMessages.last?.content, "4183")
        XCTAssertEqual(secondRequestMessages.last?.toolCallId, "call_1")
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

    /// Confirmed live: a server can list a model in its own image-generation
    /// catalog whose generation route still 404s — a provider-registration
    /// quirk, not something a fixed "pick the first one" can paper over.
    func test_sendMediaPrompt_firstCandidateNotFound_retriesNextCandidate() async throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)
        let fakeChat = FakeChatCompleting(deltas: [], error: nil)
        let fakeMedia = FakeMediaGenerating()
        fakeMedia.catalog = [
            ModelInfo(id: "broken/model", ownedBy: "broken", type: "image"),
            ModelInfo(id: "working/model", ownedBy: "working", type: "image"),
        ]
        fakeMedia.outcomesByModel = [
            "broken/model": .failure(OmniRouteError.invalidResponse(statusCode: 404)),
            "working/model": .success(.inlineData(Data("fake".utf8), contentType: "image/png")),
        ]
        let viewModel = makeViewModel(conversation: conversation, client: fakeChat, context: context, mediaClient: fakeMedia)

        await viewModel.sendMediaPrompt("un chat", kind: .image)

        XCTAssertNil(viewModel.currentError)
        XCTAssertEqual(fakeMedia.attemptedModelIDs, ["broken/model", "working/model"])
        XCTAssertEqual(conversation.orderedMessages.last?.mediaItem?.modelID, "working/model")
    }

    func test_sendMediaPrompt_firstCandidateAuthFailed_retriesNextCandidate() async throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)
        let fakeChat = FakeChatCompleting(deltas: [], error: nil)
        let fakeMedia = FakeMediaGenerating()
        fakeMedia.catalog = [
            ModelInfo(id: "revoked-key/model", ownedBy: "revoked-key", type: "image"),
            ModelInfo(id: "working/model", ownedBy: "working", type: "image"),
        ]
        fakeMedia.outcomesByModel = [
            "revoked-key/model": .failure(OmniRouteError.authenticationFailed),
            "working/model": .success(.inlineData(Data("fake".utf8), contentType: "image/png")),
        ]
        let viewModel = makeViewModel(conversation: conversation, client: fakeChat, context: context, mediaClient: fakeMedia)

        await viewModel.sendMediaPrompt("un chat", kind: .image)

        XCTAssertNil(viewModel.currentError)
        XCTAssertEqual(fakeMedia.attemptedModelIDs, ["revoked-key/model", "working/model"])
        XCTAssertEqual(conversation.orderedMessages.last?.mediaItem?.modelID, "working/model")
    }

    func test_sendMediaPrompt_nonNotFoundError_doesNotRetryOtherCandidates() async throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)
        let fakeChat = FakeChatCompleting(deltas: [], error: nil)
        let fakeMedia = FakeMediaGenerating()
        fakeMedia.catalog = [
            ModelInfo(id: "no-budget/model", ownedBy: "x", type: "image"),
            ModelInfo(id: "unreached/model", ownedBy: "x", type: "image"),
        ]
        fakeMedia.outcomesByModel = [
            "no-budget/model": .failure(OmniRouteError.rateLimited(retryAfterSeconds: nil)),
        ]
        let viewModel = makeViewModel(conversation: conversation, client: fakeChat, context: context, mediaClient: fakeMedia)

        await viewModel.sendMediaPrompt("un chat", kind: .image)

        XCTAssertNotNil(viewModel.currentError)
        XCTAssertEqual(fakeMedia.attemptedModelIDs, ["no-budget/model"])
    }

    func test_transcribeAudio_success_returnsRealText() async throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)
        let fakeChat = FakeChatCompleting(deltas: [], error: nil)
        let fakeTranscription = FakeAudioTranscribing()
        fakeTranscription.outcomesByModel = ["fake/transcriber": .success(TranscriptionResult(text: "Bonjour tout le monde"))]
        let viewModel = makeViewModel(conversation: conversation, client: fakeChat, context: context, transcriptionClient: fakeTranscription)

        let text = try await viewModel.transcribeAudio(fileData: Data("audio".utf8), fileName: "memo.mp3")

        XCTAssertEqual(text, "Bonjour tout le monde")
    }

    func test_transcribeAudio_firstCandidateNotFound_retriesNextCandidate() async throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)
        let fakeChat = FakeChatCompleting(deltas: [], error: nil)
        let fakeTranscription = FakeAudioTranscribing()
        fakeTranscription.catalog = [
            ModelInfo(id: "broken/model", ownedBy: "broken"),
            ModelInfo(id: "working/model", ownedBy: "working"),
        ]
        fakeTranscription.outcomesByModel = [
            "broken/model": .failure(OmniRouteError.invalidResponse(statusCode: 404)),
            "working/model": .success(TranscriptionResult(text: "ça marche")),
        ]
        let viewModel = makeViewModel(conversation: conversation, client: fakeChat, context: context, transcriptionClient: fakeTranscription)

        let text = try await viewModel.transcribeAudio(fileData: Data(), fileName: "memo.mp3")

        XCTAssertEqual(text, "ça marche")
        XCTAssertEqual(fakeTranscription.attemptedModelIDs, ["broken/model", "working/model"])
    }

    func test_transcribeAudio_nonRetryableError_surfacesImmediately() async throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)
        let fakeChat = FakeChatCompleting(deltas: [], error: nil)
        let fakeTranscription = FakeAudioTranscribing()
        fakeTranscription.catalog = [
            ModelInfo(id: "no-quota/model", ownedBy: "x"),
            ModelInfo(id: "unreached/model", ownedBy: "x"),
        ]
        fakeTranscription.outcomesByModel = [
            "no-quota/model": .failure(OmniRouteError.rateLimited(retryAfterSeconds: nil)),
        ]
        let viewModel = makeViewModel(conversation: conversation, client: fakeChat, context: context, transcriptionClient: fakeTranscription)

        do {
            _ = try await viewModel.transcribeAudio(fileData: Data(), fileName: "memo.mp3")
            XCTFail("expected rateLimited to surface immediately")
        } catch OmniRouteError.rateLimited {
            XCTAssertEqual(fakeTranscription.attemptedModelIDs, ["no-quota/model"])
        }
    }

    func test_transcribeAudio_emptyCatalog_throwsClearError() async throws {
        let context = try makeContext()
        let conversation = Conversation(title: "Test", defaultModelID: "auto")
        context.insert(conversation)
        let fakeChat = FakeChatCompleting(deltas: [], error: nil)
        let fakeTranscription = FakeAudioTranscribing()
        fakeTranscription.catalog = []
        let viewModel = makeViewModel(conversation: conversation, client: fakeChat, context: context, transcriptionClient: fakeTranscription)

        do {
            _ = try await viewModel.transcribeAudio(fileData: Data(), fileName: "memo.mp3")
            XCTFail("expected an error for an empty catalog")
        } catch {
            // expected — any thrown error is acceptable, the message just needs to be clear
        }
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
