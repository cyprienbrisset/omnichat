import Foundation
import SwiftData

@Model
final class Conversation {
    var title: String
    var createdAt: Date
    var defaultModelID: String
    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message] = []

    init(title: String, defaultModelID: String, createdAt: Date = Date()) {
        self.title = title
        self.defaultModelID = defaultModelID
        self.createdAt = createdAt
    }

    /// SwiftData's to-many relationships are backed by an unordered store, so
    /// `messages` itself must never be relied on for chronological order.
    /// This is the single source of truth for message ordering across the app.
    var orderedMessages: [Message] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }

    /// Conversation-level telemetry aggregate, computed purely from whatever
    /// the persisted assistant messages actually captured — never
    /// fabricated, simply absent where no message carried a given field.
    var telemetryTotals: ConversationTelemetryTotals {
        let assistantMessages = orderedMessages.filter { $0.role == "assistant" }
        var tokensIn = 0
        var tokensOut = 0
        var cost = 0.0
        var cacheHits = 0
        var cacheEligible = 0
        for message in assistantMessages {
            if let value = message.tokensIn { tokensIn += value }
            if let value = message.tokensOut { tokensOut += value }
            if let value = message.responseCostUSD { cost += value }
            if let hit = message.cacheHit {
                cacheEligible += 1
                if hit { cacheHits += 1 }
            }
        }
        let lastRouted = assistantMessages.last { $0.routingProvider != nil || $0.routingStrategy != nil }
        return ConversationTelemetryTotals(
            totalTokensIn: tokensIn,
            totalTokensOut: tokensOut,
            totalCostUSD: cost,
            cacheHits: cacheHits,
            cacheEligibleTurns: cacheEligible,
            lastRoutingStrategy: lastRouted?.routingStrategy,
            lastRoutingProvider: lastRouted?.routingProvider,
            lastRoutingLatencyMs: lastRouted?.routingLatencyMs
        )
    }
}

struct ConversationTelemetryTotals: Equatable {
    let totalTokensIn: Int
    let totalTokensOut: Int
    let totalCostUSD: Double
    let cacheHits: Int
    let cacheEligibleTurns: Int
    let lastRoutingStrategy: String?
    let lastRoutingProvider: String?
    let lastRoutingLatencyMs: Double?

    var hasAnyData: Bool {
        totalTokensIn > 0 || totalTokensOut > 0 || totalCostUSD > 0 || cacheEligibleTurns > 0 || lastRoutingProvider != nil || lastRoutingStrategy != nil
    }
}
