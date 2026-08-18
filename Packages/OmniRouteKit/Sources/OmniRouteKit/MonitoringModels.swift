import Foundation

/// Provider health summary from `/api/monitoring/health`. The field names
/// are the ones the API reference documents — but confirmed empirically
/// against a live OmniRoute 3.8.49 instance, they live one level deeper
/// than a flat top-level read would assume, nested under `providerSummary`
/// alongside a much larger process-health payload (node version, memory,
/// circuit breakers, quota monitor, sessions, etc.) this app doesn't need.
public struct MonitoringHealth: Decodable, Sendable, Equatable {
    public let catalogCount: Int
    public let configuredCount: Int
    public let activeCount: Int
    public let monitoredCount: Int

    private enum CodingKeys: String, CodingKey {
        case providerSummary
    }

    private enum ProviderSummaryKeys: String, CodingKey {
        case catalogCount, configuredCount, activeCount, monitoredCount
    }

    public init(catalogCount: Int, configuredCount: Int, activeCount: Int, monitoredCount: Int) {
        self.catalogCount = catalogCount
        self.configuredCount = configuredCount
        self.activeCount = activeCount
        self.monitoredCount = monitoredCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let summary = try container.nestedContainer(keyedBy: ProviderSummaryKeys.self, forKey: .providerSummary)
        catalogCount = try summary.decode(Int.self, forKey: .catalogCount)
        configuredCount = try summary.decode(Int.self, forKey: .configuredCount)
        activeCount = try summary.decode(Int.self, forKey: .activeCount)
        monitoredCount = try summary.decode(Int.self, forKey: .monitoredCount)
    }
}
