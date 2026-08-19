import Foundation
import SwiftData

/// A Fusion session — deliberately its own store, separate from
/// `Conversation`: a fusion round isn't a single model's reply, it's N
/// source responses synthesized by a judge, and mixing the two would make
/// the normal conversation list lie about what actually produced a message.
@Model
final class FusionSession {
    var title: String
    var createdAt: Date
    /// `"auto"` (OmniRoute's own routing, real provider resolved per round
    /// from the response's telemetry) or an explicit `provider/model` id —
    /// same two options as a normal conversation's default model.
    var judgeModelID: String
    @Relationship(deleteRule: .cascade, inverse: \FusionRound.session)
    var rounds: [FusionRound] = []

    init(title: String, judgeModelID: String = "auto", createdAt: Date = Date()) {
        self.title = title
        self.judgeModelID = judgeModelID
        self.createdAt = createdAt
    }

    /// SwiftData's to-many relationships are backed by an unordered store —
    /// this is the single source of truth for chronological order.
    var orderedRounds: [FusionRound] {
        rounds.sorted { $0.createdAt < $1.createdAt }
    }
}

/// One prompt's worth of fusion: what the user asked, the judge's fused
/// answer, and every source response that fed it.
@Model
final class FusionRound {
    var prompt: String
    var createdAt: Date
    var fusedContent: String = ""
    var fusedIsIncomplete: Bool = false
    /// What the judge was set to *at the time this round ran* — the
    /// session's `judgeModelID` is mutable, so relying on its current value
    /// to describe a past round would misattribute it if the user changed
    /// the judge afterwards.
    var judgeModelIDAtRoundTime: String = "auto"
    /// The real model that answered, captured from the response's own
    /// telemetry — set even when the judge was `"auto"`, since
    /// `/v1/chat/completions` (unlike media generation) really does
    /// support `"auto"` server-side and reports back which provider it
    /// picked. Never a guess: absent if the telemetry header wasn't
    /// present on this response.
    var resolvedJudgeModelID: String?
    var session: FusionSession?
    @Relationship(deleteRule: .cascade, inverse: \FusionSourceResponse.round)
    var sourceResponses: [FusionSourceResponse] = []

    init(prompt: String, createdAt: Date = Date()) {
        self.prompt = prompt
        self.createdAt = createdAt
    }

    /// Preserves the order source models were added in (not alphabetical,
    /// not insertion-into-the-unordered-relationship order).
    var orderedSourceResponses: [FusionSourceResponse] {
        sourceResponses.sorted { $0.sortIndex < $1.sortIndex }
    }
}

/// One model's real, independent answer to a fusion round's prompt — kept
/// even after the judge synthesizes them, so the synthesis stays checkable
/// against what actually fed it.
@Model
final class FusionSourceResponse {
    var modelID: String
    var content: String = ""
    var isIncomplete: Bool = false
    var sortIndex: Int = 0
    var round: FusionRound?

    init(modelID: String, content: String = "", isIncomplete: Bool = false, sortIndex: Int = 0) {
        self.modelID = modelID
        self.content = content
        self.isIncomplete = isIncomplete
        self.sortIndex = sortIndex
    }
}
