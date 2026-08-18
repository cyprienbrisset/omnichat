import Foundation

/// Routing and cost telemetry parsed from OmniRoute's `X-OmniRoute-*` response
/// headers. Every field is optional and independently absent-tolerant: the
/// API reference only confirms the cost/token set on non-streaming responses,
/// so a streaming chat completion may carry the routing decision alone, all
/// of it, or none of it. Callers must not assume any particular subset.
public struct RequestTelemetry: Sendable, Equatable {
    public let requestId: String?
    public let routingStrategy: String?
    public let routingProvider: String?
    public let routingLatencyMs: Double?
    public let responseCostUSD: Double?
    public let tokensIn: Int?
    public let tokensOut: Int?
    public let cacheHit: Bool?
    public let fallbackAttempts: Int?

    public init(
        requestId: String? = nil,
        routingStrategy: String? = nil,
        routingProvider: String? = nil,
        routingLatencyMs: Double? = nil,
        responseCostUSD: Double? = nil,
        tokensIn: Int? = nil,
        tokensOut: Int? = nil,
        cacheHit: Bool? = nil,
        fallbackAttempts: Int? = nil
    ) {
        self.requestId = requestId
        self.routingStrategy = routingStrategy
        self.routingProvider = routingProvider
        self.routingLatencyMs = routingLatencyMs
        self.responseCostUSD = responseCostUSD
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.cacheHit = cacheHit
        self.fallbackAttempts = fallbackAttempts
    }

    /// `nil` when the response carried none of the recognized headers at all
    /// — distinguishes "nothing to show" from "an empty telemetry record".
    static func parse(from response: HTTPURLResponse) -> RequestTelemetry? {
        let decision = response.value(forHTTPHeaderField: "X-OmniRoute-Decision").map(parseDecision)
        let requestId = response.value(forHTTPHeaderField: "X-OmniRoute-Request-Id")
        let cost = response.value(forHTTPHeaderField: "X-OmniRoute-Response-Cost").flatMap(Double.init)
        let tokensIn = response.value(forHTTPHeaderField: "X-OmniRoute-Tokens-In").flatMap(Int.init)
        let tokensOut = response.value(forHTTPHeaderField: "X-OmniRoute-Tokens-Out").flatMap(Int.init)
        let cacheHit = response.value(forHTTPHeaderField: "X-OmniRoute-Cache-Hit").map { $0.lowercased() == "true" }
        let fallbackAttempts = response.value(forHTTPHeaderField: "X-OmniRoute-Fallback-Attempts").flatMap(Int.init)

        let telemetry = RequestTelemetry(
            requestId: requestId,
            routingStrategy: decision?.strategy,
            routingProvider: decision?.provider,
            routingLatencyMs: decision?.latencyMs,
            responseCostUSD: cost,
            tokensIn: tokensIn,
            tokensOut: tokensOut,
            cacheHit: cacheHit,
            fallbackAttempts: fallbackAttempts
        )
        return telemetry == RequestTelemetry() ? nil : telemetry
    }

    private static func parseDecision(_ raw: String) -> (strategy: String?, provider: String?, latencyMs: Double?) {
        var strategy: String?
        var provider: String?
        var latencyMs: Double?
        for part in raw.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2 else { continue }
            switch pair[0] {
            case "strategy": strategy = pair[1]
            case "provider": provider = pair[1]
            case "latency_ms": latencyMs = Double(pair[1])
            default: break
            }
        }
        return (strategy, provider, latencyMs)
    }
}
