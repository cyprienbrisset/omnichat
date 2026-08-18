import Foundation

extension OmniRouteClient {
    /// Lists stored memories. Requires management scope — callers should
    /// check `hasManagementAccess()` first rather than relying solely on
    /// the 401/403 this throws when the key lacks it.
    public func listMemories() async throws -> [MemoryEntry] {
        var attempt = 1
        while true {
            do {
                let request = try authorizedManagementRequest(path: "api/memory")
                let (data, response) = try await session.data(for: request)
                _ = try Self.requireSuccess(response)
                do {
                    return try parseMemoryListResponse(data)
                } catch {
                    throw OmniRouteError.unknown(description: "Réponse mémoire inattendue : \(error)")
                }
            } catch {
                let mapped = Self.mapNetworkingError(error)
                guard retryPolicy.shouldRetry(attempt: attempt, error: mapped) else { throw mapped }
                try await Task.sleep(for: .seconds(retryPolicy.delay(forAttempt: attempt)))
                attempt += 1
            }
        }
    }

    /// Deletes one memory by id.
    public func deleteMemory(id: String) async throws {
        var attempt = 1
        while true {
            do {
                var request = try authorizedManagementRequest(path: "api/memory/\(id)")
                request.httpMethod = "DELETE"
                let (_, response) = try await session.data(for: request)
                _ = try Self.requireSuccess(response)
                return
            } catch {
                let mapped = Self.mapNetworkingError(error)
                guard retryPolicy.shouldRetry(attempt: attempt, error: mapped) else { throw mapped }
                try await Task.sleep(for: .seconds(retryPolicy.delay(forAttempt: attempt)))
                attempt += 1
            }
        }
    }
}
