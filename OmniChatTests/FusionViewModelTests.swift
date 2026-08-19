import XCTest
import SwiftData
@testable import OmniChat
@testable import OmniRouteKit

/// Routes each `streamChatCompletion` call to a per-model canned outcome —
/// needed because a fusion round calls the *same* client for every source
/// model plus the judge, each of which must answer differently.
private final class FakeChatCompletingByModel: ChatCompleting, @unchecked Sendable {
    struct Outcome {
        let deltas: [ChatDelta]
        let error: OmniRouteError?
    }
    var outcomesByModel: [String: Outcome] = [:]
    private(set) var capturedRequests: [ChatCompletionRequest] = []

    func streamChatCompletion(_ request: ChatCompletionRequest) -> AsyncThrowingStream<ChatDelta, Error> {
        capturedRequests.append(request)
        let outcome = outcomesByModel[request.model]
        return AsyncThrowingStream { continuation in
            for delta in outcome?.deltas ?? [] { continuation.yield(delta) }
            if let error = outcome?.error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }
}

@MainActor
final class FusionViewModelTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([FusionSession.self, FusionRound.self, FusionSourceResponse.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    func test_sendFusionPrompt_allSourcesSucceed_persistsRoundWithBothSourcesAndFusedAnswer() async throws {
        let context = try makeContext()
        let session = FusionSession(title: "Test", judgeModelID: "judge/model")
        context.insert(session)
        let client = FakeChatCompletingByModel()
        client.outcomesByModel = [
            "a/model": .init(deltas: [ChatDelta(content: "Réponse A", isFinal: true)], error: nil),
            "b/model": .init(deltas: [ChatDelta(content: "Réponse B", isFinal: true)], error: nil),
            "judge/model": .init(deltas: [ChatDelta(content: "Synthèse", isFinal: true)], error: nil),
        ]
        let viewModel = FusionViewModel(session: session, client: client, context: context)
        viewModel.addSourceModel("a/model")
        viewModel.addSourceModel("b/model")

        await viewModel.sendFusionPrompt("Quelle est la capitale ?")

        XCTAssertEqual(viewModel.fusedContent, "Synthèse")
        XCTAssertNil(viewModel.fusedError)
        XCTAssertEqual(session.orderedRounds.count, 1)
        let round = try XCTUnwrap(session.orderedRounds.first)
        XCTAssertEqual(round.prompt, "Quelle est la capitale ?")
        XCTAssertEqual(round.fusedContent, "Synthèse")
        XCTAssertFalse(round.fusedIsIncomplete)
        XCTAssertEqual(round.judgeModelIDAtRoundTime, "judge/model")
        XCTAssertEqual(round.resolvedJudgeModelID, "judge/model")
        XCTAssertEqual(round.orderedSourceResponses.map(\.modelID), ["a/model", "b/model"])
        XCTAssertEqual(round.orderedSourceResponses.map(\.content), ["Réponse A", "Réponse B"])
    }

    func test_sendFusionPrompt_synthesisRequest_includesOriginalPromptAndEverySourceAnswer() async throws {
        let context = try makeContext()
        let session = FusionSession(title: "Test", judgeModelID: "judge/model")
        context.insert(session)
        let client = FakeChatCompletingByModel()
        client.outcomesByModel = [
            "a/model": .init(deltas: [ChatDelta(content: "Réponse A", isFinal: true)], error: nil),
            "judge/model": .init(deltas: [ChatDelta(content: "Synthèse", isFinal: true)], error: nil),
        ]
        let viewModel = FusionViewModel(session: session, client: client, context: context)
        viewModel.addSourceModel("a/model")

        await viewModel.sendFusionPrompt("Question ?")

        let judgeRequest = try XCTUnwrap(client.capturedRequests.last { $0.model == "judge/model" })
        let userMessage = try XCTUnwrap(judgeRequest.messages.last { $0.role == .user })
        XCTAssertTrue(userMessage.content.contains("Question ?"))
        XCTAssertTrue(userMessage.content.contains("a/model"))
        XCTAssertTrue(userMessage.content.contains("Réponse A"))
    }

    func test_sendFusionPrompt_oneSourceFails_stillFusesFromSucceededSourceOnly() async throws {
        let context = try makeContext()
        let session = FusionSession(title: "Test", judgeModelID: "judge/model")
        context.insert(session)
        let client = FakeChatCompletingByModel()
        client.outcomesByModel = [
            "broken/model": .init(deltas: [], error: .invalidResponse(statusCode: 404)),
            "working/model": .init(deltas: [ChatDelta(content: "Réponse B", isFinal: true)], error: nil),
            "judge/model": .init(deltas: [ChatDelta(content: "Synthèse", isFinal: true)], error: nil),
        ]
        let viewModel = FusionViewModel(session: session, client: client, context: context)
        viewModel.addSourceModel("broken/model")
        viewModel.addSourceModel("working/model")

        await viewModel.sendFusionPrompt("Question ?")

        XCTAssertNil(viewModel.fusedError)
        XCTAssertEqual(viewModel.fusedContent, "Synthèse")
        let round = try XCTUnwrap(session.orderedRounds.first)
        XCTAssertEqual(round.orderedSourceResponses.map(\.modelID), ["working/model"], "a failed source produced no real answer, so it isn't recorded as one")
    }

    func test_sendFusionPrompt_allSourcesFail_surfacesErrorAndNeverCallsJudge() async throws {
        let context = try makeContext()
        let session = FusionSession(title: "Test", judgeModelID: "judge/model")
        context.insert(session)
        let client = FakeChatCompletingByModel()
        client.outcomesByModel = [
            "a/model": .init(deltas: [], error: .invalidResponse(statusCode: 404)),
            "b/model": .init(deltas: [], error: .invalidResponse(statusCode: 404)),
        ]
        let viewModel = FusionViewModel(session: session, client: client, context: context)
        viewModel.addSourceModel("a/model")
        viewModel.addSourceModel("b/model")

        await viewModel.sendFusionPrompt("Question ?")

        XCTAssertNotNil(viewModel.fusedError)
        XCTAssertTrue(session.orderedRounds.isEmpty)
        XCTAssertFalse(client.capturedRequests.contains { $0.model == "judge/model" })
    }

    func test_sendFusionPrompt_autoJudge_resolvesRealModelFromTelemetry() async throws {
        let context = try makeContext()
        let session = FusionSession(title: "Test", judgeModelID: "auto")
        context.insert(session)
        let client = FakeChatCompletingByModel()
        let telemetry = RequestTelemetry(routingProvider: "openai/gpt-4o")
        client.outcomesByModel = [
            "a/model": .init(deltas: [ChatDelta(content: "Réponse A", isFinal: true)], error: nil),
            "auto": .init(deltas: [ChatDelta(content: "Synthèse", isFinal: false, telemetry: telemetry), ChatDelta(content: "", isFinal: true)], error: nil),
        ]
        let viewModel = FusionViewModel(session: session, client: client, context: context)
        viewModel.addSourceModel("a/model")

        await viewModel.sendFusionPrompt("Question ?")

        XCTAssertEqual(viewModel.resolvedJudgeModelID, "openai/gpt-4o")
        let round = try XCTUnwrap(session.orderedRounds.first)
        XCTAssertEqual(round.judgeModelIDAtRoundTime, "auto")
        XCTAssertEqual(round.resolvedJudgeModelID, "openai/gpt-4o", "the round records which real model answered, not the literal \"auto\" alias")
    }

    func test_addSourceModel_duplicateModelID_addedOnlyOnce() {
        let session = FusionSession(title: "Test")
        let client = FakeChatCompletingByModel()
        let viewModel = FusionViewModel(session: session, client: client, context: try! makeContext())

        viewModel.addSourceModel("a/model")
        viewModel.addSourceModel("a/model")

        XCTAssertEqual(viewModel.sourceColumns.count, 1)
    }
}
