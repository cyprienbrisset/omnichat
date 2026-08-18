import Foundation

extension OmniRouteClient {
    /// Lists the embedded MCP server's scoped tools. Requires management
    /// scope — callers should check `hasManagementAccess()` first rather
    /// than relying solely on the 401/403 this throws when the key lacks it.
    public func listMCPTools() async throws -> [MCPTool] {
        var attempt = 1
        while true {
            do {
                let request = try authorizedManagementRequest(path: "api/mcp/tools")
                let (data, response) = try await session.data(for: request)
                _ = try Self.requireSuccess(response)
                do {
                    return try parseMCPToolListResponse(data)
                } catch {
                    throw OmniRouteError.unknown(description: "Réponse MCP (outils) inattendue : \(error)")
                }
            } catch {
                let mapped = Self.mapNetworkingError(error)
                guard retryPolicy.shouldRetry(attempt: attempt, error: mapped) else { throw mapped }
                try await Task.sleep(for: .seconds(retryPolicy.delay(forAttempt: attempt)))
                attempt += 1
            }
        }
    }

    /// Raw heartbeat/transport snapshot from `/api/mcp/status` — see
    /// `MCPRawSnapshot` for why this isn't a typed model.
    public func fetchMCPStatus() async throws -> MCPRawSnapshot {
        try await fetchMCPRawSnapshot(path: "api/mcp/status")
    }

    /// Raw aggregate audit stats from `/api/mcp/audit/stats`.
    public func fetchMCPAuditStats() async throws -> MCPRawSnapshot {
        try await fetchMCPRawSnapshot(path: "api/mcp/audit/stats")
    }

    private func fetchMCPRawSnapshot(path: String) async throws -> MCPRawSnapshot {
        var attempt = 1
        while true {
            do {
                let request = try authorizedManagementRequest(path: path)
                let (data, response) = try await session.data(for: request)
                _ = try Self.requireSuccess(response)
                do {
                    return try parseMCPRawSnapshot(data)
                } catch {
                    throw OmniRouteError.unknown(description: "Réponse MCP inattendue : \(error)")
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
