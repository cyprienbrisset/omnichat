import Foundation

extension OmniRouteClient {
    /// Real provider health/count summary from `/api/monitoring/health` —
    /// backs the sidebar's health indicator. Requires management scope like
    /// the other `/api/*` reads this app makes.
    public func fetchMonitoringHealth() async throws -> MonitoringHealth {
        var attempt = 1
        while true {
            do {
                let request = try authorizedManagementRequest(path: "api/monitoring/health")
                let (data, response) = try await session.data(for: request)
                _ = try Self.requireSuccess(response)
                do {
                    return try JSONDecoder().decode(MonitoringHealth.self, from: data)
                } catch {
                    throw OmniRouteError.unknown(description: "Réponse de santé inattendue : \(error)")
                }
            } catch {
                let mapped = Self.mapNetworkingError(error)
                guard retryPolicy.shouldRetry(attempt: attempt, error: mapped) else { throw mapped }
                try await Task.sleep(for: .seconds(retryPolicy.delay(forAttempt: attempt)))
                attempt += 1
            }
        }
    }
}
