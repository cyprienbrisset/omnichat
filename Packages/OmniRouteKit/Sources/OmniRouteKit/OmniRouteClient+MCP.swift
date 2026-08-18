import Foundation

/// The server's real JSON error envelope, confirmed empirically against a
/// live OmniRoute 3.8.49 instance: `{"error":{"code","message",...}}`.
private struct MCPServerErrorEnvelope: Decodable {
    struct Body: Decodable { let code: String; let message: String }
    let error: Body
}

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
                try Self.throwIfLocalOnly(data: data, response: response)
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

    /// Real, retrospective log of MCP tool calls actually made against this
    /// server's MCP transports — the closest honest signal this app has
    /// into MCP tool usage, since the API reference doesn't document
    /// OpenAI-style `tools`/`tool_calls` support on `/v1/chat/completions`,
    /// so OmniChat can't yet confirm it could invoke tools inline itself.
    public func fetchMCPAudit(limit: Int = 50) async throws -> [MCPRawSnapshot] {
        var attempt = 1
        while true {
            do {
                guard var components = URLComponents(
                    url: managementBaseURL.appendingPathComponent("api/mcp/audit"),
                    resolvingAgainstBaseURL: false
                ) else {
                    throw OmniRouteError.unknown(description: "URL d'audit MCP invalide")
                }
                components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
                guard let url = components.url else {
                    throw OmniRouteError.unknown(description: "URL d'audit MCP invalide")
                }
                var request = URLRequest(url: url)
                if let apiKey = try credentialStore.apiKey(for: profile.id) {
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                }
                let (data, response) = try await session.data(for: request)
                try Self.throwIfLocalOnly(data: data, response: response)
                _ = try Self.requireSuccess(response)
                do {
                    return try parseMCPAuditListResponse(data)
                } catch {
                    throw OmniRouteError.unknown(description: "Réponse d'audit MCP inattendue : \(error)")
                }
            } catch {
                let mapped = Self.mapNetworkingError(error)
                guard retryPolicy.shouldRetry(attempt: attempt, error: mapped) else { throw mapped }
                try await Task.sleep(for: .seconds(retryPolicy.delay(forAttempt: attempt)))
                attempt += 1
            }
        }
    }

    private func fetchMCPRawSnapshot(path: String) async throws -> MCPRawSnapshot {
        var attempt = 1
        while true {
            do {
                let request = try authorizedManagementRequest(path: path)
                let (data, response) = try await session.data(for: request)
                try Self.throwIfLocalOnly(data: data, response: response)
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

    /// Confirmed empirically against a live OmniRoute instance: every
    /// `/api/mcp/*` route returns `403 {"error":{"code":"LOCAL_ONLY",...}}`
    /// when reached from anywhere but the machine hosting OmniRoute itself
    /// — regardless of the API key's rights. Without this check, that 403
    /// falls through to `.authenticationFailed` and tells the user to fix a
    /// key that was never the problem; a self-hosted, remotely-accessed
    /// OmniRoute (this app's most common setup) can never pass this check.
    private static func throwIfLocalOnly(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 403,
              let envelope = try? JSONDecoder().decode(MCPServerErrorEnvelope.self, from: data),
              envelope.error.code == "LOCAL_ONLY" else {
            return
        }
        throw OmniRouteError.unknown(
            description: "Le serveur MCP n'est accessible que depuis la machine qui héberge OmniRoute (localhost) — indisponible pour une instance distante, quels que soient les droits de la clé."
        )
    }
}
