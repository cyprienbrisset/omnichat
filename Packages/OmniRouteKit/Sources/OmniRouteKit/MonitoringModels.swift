import Foundation

/// Provider health summary from `/api/monitoring/health`. The field names
/// are the ones the API reference documents — but confirmed empirically
/// against a live OmniRoute 3.8.49 instance, the counts live one level
/// deeper than a flat top-level read would assume, nested under
/// `providerSummary` alongside a much larger process-health payload (node
/// version, memory, circuit breakers, quota monitor, sessions, etc.).
/// `version`/`uptimeSeconds`/`activeConnections`/`credentialHealth`/
/// `circuitBreakers`/`providerBreakers` are all confirmed present in that
/// same real payload — everything else in it (memory, sessions, quota
/// monitor, dedup, cryptography…) stays unused since nothing in the app
/// needs it yet.
public struct MonitoringHealth: Decodable, Sendable, Equatable {
    public let status: String
    public let version: String
    public let uptimeSeconds: Double
    public let activeConnections: Int
    public let catalogCount: Int
    public let configuredCount: Int
    public let activeCount: Int
    public let monitoredCount: Int
    public let credentialHealth: CredentialHealthSummary
    public let circuitBreakers: CircuitBreakerSummary
    public let providerBreakers: [ProviderBreaker]

    private enum CodingKeys: String, CodingKey {
        case status, version, uptime, activeConnections, providerSummary, credentialHealth, circuitBreakers, providerBreakers
    }

    private enum ProviderSummaryKeys: String, CodingKey {
        case catalogCount, configuredCount, activeCount, monitoredCount
    }

    public init(
        status: String,
        version: String,
        uptimeSeconds: Double,
        activeConnections: Int,
        catalogCount: Int,
        configuredCount: Int,
        activeCount: Int,
        monitoredCount: Int,
        credentialHealth: CredentialHealthSummary,
        circuitBreakers: CircuitBreakerSummary,
        providerBreakers: [ProviderBreaker]
    ) {
        self.status = status
        self.version = version
        self.uptimeSeconds = uptimeSeconds
        self.activeConnections = activeConnections
        self.catalogCount = catalogCount
        self.configuredCount = configuredCount
        self.activeCount = activeCount
        self.monitoredCount = monitoredCount
        self.credentialHealth = credentialHealth
        self.circuitBreakers = circuitBreakers
        self.providerBreakers = providerBreakers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "?"
        uptimeSeconds = try container.decodeIfPresent(Double.self, forKey: .uptime) ?? 0
        activeConnections = try container.decodeIfPresent(Int.self, forKey: .activeConnections) ?? 0
        let summary = try container.nestedContainer(keyedBy: ProviderSummaryKeys.self, forKey: .providerSummary)
        catalogCount = try summary.decode(Int.self, forKey: .catalogCount)
        configuredCount = try summary.decode(Int.self, forKey: .configuredCount)
        activeCount = try summary.decode(Int.self, forKey: .activeCount)
        monitoredCount = try summary.decode(Int.self, forKey: .monitoredCount)
        credentialHealth = try container.decodeIfPresent(CredentialHealthSummary.self, forKey: .credentialHealth) ?? .empty
        circuitBreakers = try container.decodeIfPresent(CircuitBreakerSummary.self, forKey: .circuitBreakers) ?? .empty
        providerBreakers = try container.decodeIfPresent([ProviderBreaker].self, forKey: .providerBreakers) ?? []
    }
}

/// Real fields confirmed against a live instance: `{"total":31,"healthy":31,
/// "failed":0,"unknown":0,"stale":0}`.
public struct CredentialHealthSummary: Codable, Sendable, Equatable {
    public let total: Int
    public let healthy: Int
    public let failed: Int
    public let unknown: Int
    public let stale: Int

    public static let empty = CredentialHealthSummary(total: 0, healthy: 0, failed: 0, unknown: 0, stale: 0)

    public init(total: Int, healthy: Int, failed: Int, unknown: Int, stale: Int) {
        self.total = total
        self.healthy = healthy
        self.failed = failed
        self.unknown = unknown
        self.stale = stale
    }
}

/// Real fields confirmed against a live instance: `{"open":0,"halfOpen":0,
/// "degraded":0,"closed":1,"total":1}`.
public struct CircuitBreakerSummary: Codable, Sendable, Equatable {
    public let open: Int
    public let halfOpen: Int
    public let degraded: Int
    public let closed: Int
    public let total: Int

    public static let empty = CircuitBreakerSummary(open: 0, halfOpen: 0, degraded: 0, closed: 0, total: 0)

    public init(open: Int, halfOpen: Int, degraded: Int, closed: Int, total: Int) {
        self.open = open
        self.halfOpen = halfOpen
        self.degraded = degraded
        self.closed = closed
        self.total = total
    }
}

/// Real fields confirmed against a live instance: `{"provider":"gemini-web",
/// "state":"CLOSED","failureCount":1,"lastFailure":"2026-08-19T09:33:52.714Z",
/// "retryAfterMs":0}`.
public struct ProviderBreaker: Codable, Sendable, Equatable, Identifiable {
    public var id: String { provider }
    public let provider: String
    public let state: String
    public let failureCount: Int
    public let lastFailure: String?
    public let retryAfterMs: Int?

    public init(provider: String, state: String, failureCount: Int, lastFailure: String?, retryAfterMs: Int?) {
        self.provider = provider
        self.state = state
        self.failureCount = failureCount
        self.lastFailure = lastFailure
        self.retryAfterMs = retryAfterMs
    }
}
