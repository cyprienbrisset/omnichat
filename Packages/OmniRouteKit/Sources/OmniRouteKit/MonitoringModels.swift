import Foundation

/// Provider health summary from `/api/monitoring/health` — field names are
/// the ones the API reference documents explicitly for this route.
public struct MonitoringHealth: Decodable, Sendable, Equatable {
    public let catalogCount: Int
    public let configuredCount: Int
    public let activeCount: Int
    public let monitoredCount: Int

    public init(catalogCount: Int, configuredCount: Int, activeCount: Int, monitoredCount: Int) {
        self.catalogCount = catalogCount
        self.configuredCount = configuredCount
        self.activeCount = activeCount
        self.monitoredCount = monitoredCount
    }
}
