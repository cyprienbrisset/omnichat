import Foundation
import SwiftData

@Model
final class Message {
    var role: String
    var content: String
    var createdAt: Date
    var isIncomplete: Bool
    var conversation: Conversation?
    var mediaItem: MediaItem?

    // Telemetry parsed from OmniRoute's `X-OmniRoute-*` response headers, when
    // present (see `RequestTelemetry` in OmniRouteKit). All optional and
    // independently absent — a streaming response may not carry every field.
    var routingStrategy: String?
    var routingProvider: String?
    var routingLatencyMs: Double?
    var responseCostUSD: Double?
    var tokensIn: Int?
    var tokensOut: Int?
    var cacheHit: Bool?

    // Set when this assistant turn called a local tool (see
    // `ChatViewModel.localTools`) — real name/arguments/result of an actual
    // call OmniChat made and executed itself, never OmniRoute's MCP catalog
    // (a remote OmniRoute instance can't reach that surface; see
    // `OmniRouteClient+MCP.swift`).
    var toolName: String?
    var toolArguments: String?
    var toolResult: String?

    init(role: String, content: String, isIncomplete: Bool = false, createdAt: Date = Date()) {
        self.role = role
        self.content = content
        self.isIncomplete = isIncomplete
        self.createdAt = createdAt
    }

    /// Compact, mono-friendly one-line summary of whatever telemetry is
    /// present. `nil` when nothing was captured — never fabricates a value.
    var telemetrySummary: String? {
        var parts: [String] = []
        switch (routingStrategy, routingProvider) {
        case let (strategy?, provider?) where strategy != "single":
            parts.append("\(strategy) → \(provider)")
        case (_, let provider?):
            parts.append(provider)
        case (let strategy?, nil):
            parts.append(strategy)
        default:
            break
        }
        if let routingLatencyMs {
            parts.append("\(Int(routingLatencyMs)) ms")
        }
        if let responseCostUSD, responseCostUSD > 0 {
            parts.append(String(format: "$%.4f", responseCostUSD))
        }
        if cacheHit == true {
            parts.append("cache")
        }
        if let tokensIn, let tokensOut {
            parts.append("\(tokensIn)→\(tokensOut) tok")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
