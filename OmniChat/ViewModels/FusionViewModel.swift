import Foundation
import SwiftData
import Observation
import OmniRouteKit

/// Drives one `FusionSession`: N source models answer the same prompt
/// independently (each a real `ComparisonColumnViewModel` stream, exactly
/// like the Comparison screen), then a judge model reads all of them and
/// synthesizes a single fused answer. Unlike Comparison, this persists —
/// into `FusionSession`/`FusionRound`, never into the normal
/// `Conversation`/`Message` store, since a fused answer isn't a single
/// model's reply.
@Observable
@MainActor
final class FusionViewModel {
    let session: FusionSession
    private(set) var sourceColumns: [ComparisonColumnViewModel] = []
    var judgeModelID: String
    /// True from the moment a round starts until it's fully persisted —
    /// the one signal the view needs to know whether to render the live,
    /// not-yet-persisted round instead of (or alongside) `session.rounds`.
    /// `fusedContent`/`sourceColumns` deliberately keep showing the last
    /// round's data after this goes false (same as `ComparisonColumnViewModel`
    /// between sends), so visibility can't be inferred from them alone.
    private(set) var isRunning = false
    /// The prompt the *currently running* round was sent with — the
    /// composer's own text field is cleared as soon as sending starts, so
    /// the live round view can't read it from there.
    private(set) var runningPrompt: String?
    private(set) var fusedContent = ""
    private(set) var fusedIsStreaming = false
    private(set) var fusedError: OmniRouteError?
    /// The real model that answered, read from the judge response's own
    /// telemetry — set even when `judgeModelID` is `"auto"`, since
    /// `/v1/chat/completions` supports `"auto"` server-side (unlike media
    /// generation) and reports back which provider it actually picked.
    private(set) var resolvedJudgeModelID: String?

    private let client: ChatCompleting
    private let context: ModelContext

    init(session: FusionSession, client: ChatCompleting, context: ModelContext) {
        self.session = session
        self.client = client
        self.context = context
        self.judgeModelID = session.judgeModelID
    }

    func addSourceModel(_ modelID: String) {
        guard !sourceColumns.contains(where: { $0.modelID == modelID }) else { return }
        sourceColumns.append(ComparisonColumnViewModel(modelID: modelID, client: client))
    }

    func removeSourceModel(_ column: ComparisonColumnViewModel) {
        sourceColumns.removeAll { $0.id == column.id }
    }

    /// Sends `prompt` to every source model concurrently, then — once they've
    /// all settled — asks the judge to fuse whichever ones actually
    /// answered into a single response. A source model failing doesn't
    /// abort the round; only feeding the judge zero real answers does.
    func sendFusionPrompt(_ prompt: String) async {
        guard !sourceColumns.isEmpty else { return }
        isRunning = true
        runningPrompt = prompt
        defer { isRunning = false }
        fusedContent = ""
        fusedError = nil
        resolvedJudgeModelID = nil
        session.judgeModelID = judgeModelID

        await withTaskGroup(of: Void.self) { group in
            for column in sourceColumns {
                group.addTask { await column.send(prompt) }
            }
        }

        let answered = sourceColumns.filter { $0.error == nil && !$0.content.isEmpty }
        guard !answered.isEmpty else {
            fusedError = .unknown(description: "Aucun modèle source n'a répondu — impossible de fusionner.")
            return
        }

        fusedIsStreaming = true
        defer { fusedIsStreaming = false }

        let request = ChatCompletionRequest(
            model: judgeModelID,
            messages: [
                ChatMessage(role: .system, content: Self.judgeSystemPrompt),
                ChatMessage(role: .user, content: Self.synthesisPrompt(userPrompt: prompt, sources: answered)),
            ]
        )
        do {
            for try await delta in client.streamChatCompletion(request) {
                if let provider = delta.telemetry?.routingProvider {
                    resolvedJudgeModelID = provider
                }
                fusedContent += delta.content
            }
        } catch let error as OmniRouteError {
            fusedError = error
        } catch {
            fusedError = .unknown(description: "\(error)")
        }

        persistRound(prompt: prompt, sources: answered)
    }

    private func persistRound(prompt: String, sources: [ComparisonColumnViewModel]) {
        let round = FusionRound(prompt: prompt)
        round.fusedContent = fusedContent
        round.fusedIsIncomplete = fusedError != nil
        round.judgeModelIDAtRoundTime = judgeModelID
        round.resolvedJudgeModelID = judgeModelID == "auto" ? resolvedJudgeModelID : judgeModelID
        round.session = session
        for (index, column) in sources.enumerated() {
            let response = FusionSourceResponse(modelID: column.modelID, content: column.content, sortIndex: index)
            response.round = round
            round.sourceResponses.append(response)
        }
        session.rounds.append(round)
        context.insert(round)
        try? context.save()
    }

    private static let judgeSystemPrompt = """
    Tu es un juge chargé de fusionner plusieurs réponses de modèles \
    différents à la même question en une seule réponse finale — la plus \
    complète, cohérente et exacte possible. Ne mentionne pas le fait que \
    tu synthétises plusieurs sources ; réponds directement comme si tu \
    répondais toi-même à la question.
    """

    private static func synthesisPrompt(userPrompt: String, sources: [ComparisonColumnViewModel]) -> String {
        var parts = ["Question originale :\n\(userPrompt)", "\nRéponses à fusionner :"]
        for column in sources {
            parts.append("\n--- \(column.modelID) ---\n\(column.content)")
        }
        return parts.joined(separator: "\n")
    }
}
