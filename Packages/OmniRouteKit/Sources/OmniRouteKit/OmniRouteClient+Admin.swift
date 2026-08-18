import Foundation

/// The server's real JSON error envelope, confirmed empirically against a
/// live OmniRoute 3.8.49 instance: `{"error":{"message","code"?,...}}`.
/// Used here (unlike the plain HTTP-status mapping the rest of the app
/// uses) because these admin mutations have undocumented or only
/// best-effort request schemas — when a guess is wrong, the real Zod
/// validation message is the only way to see what's actually expected.
private struct AdminServerErrorEnvelope: Decodable {
    struct Body: Decodable { let message: String }
    let error: Body
}

extension OmniRouteClient {
    // MARK: Providers
    // `/api/providers` request/response shapes aren't documented beyond
    // "List / create providers" — list/test/delete are simple REST calls
    // that don't need a body shape to work; `createProvider`'s request body
    // is a best-effort guess (name/provider slug/API key), and any real
    // validation error the server returns is surfaced verbatim rather than
    // masked, so a wrong guess is immediately visible and fixable.

    public func listProviders() async throws -> [AdminRawSnapshot] {
        try await adminGET(path: "api/providers", parse: parseAdminRawSnapshotList)
    }

    public func testProvider(id: String) async throws -> AdminRawSnapshot {
        try await adminMutate(path: "api/providers/\(id)/test", method: "POST", body: Optional<String>.none, parse: parseAdminRawSnapshot)
    }

    public func deleteProvider(id: String) async throws {
        try await adminMutateNoContent(path: "api/providers/\(id)", method: "DELETE")
    }

    public func createProvider(name: String, providerType: String, apiKey: String) async throws -> AdminRawSnapshot {
        struct Body: Encodable { let name: String; let provider: String; let apiKey: String }
        return try await adminMutate(
            path: "api/providers",
            method: "POST",
            body: Body(name: name, provider: providerType, apiKey: apiKey),
            parse: parseAdminRawSnapshot
        )
    }

    // MARK: Budget (fully documented schema)

    public func listBudgets() async throws -> [BudgetEntry] {
        try await adminGET(path: "api/usage/budget", parse: parseBudgetListResponse)
    }

    public func setBudget(_ request: SetBudgetRequest) async throws {
        try await adminMutateNoContent(path: "api/usage/budget", method: "POST", body: request)
    }

    // MARK: Token limits (fully documented schema)

    public func listTokenLimits(apiKeyId: String) async throws -> [TokenLimitEntry] {
        var attempt = 1
        while true {
            do {
                guard var components = URLComponents(
                    url: managementBaseURL.appendingPathComponent("api/usage/token-limits"),
                    resolvingAgainstBaseURL: false
                ) else {
                    throw OmniRouteError.unknown(description: "URL de limites de jetons invalide")
                }
                components.queryItems = [URLQueryItem(name: "apiKeyId", value: apiKeyId)]
                guard let url = components.url else {
                    throw OmniRouteError.unknown(description: "URL de limites de jetons invalide")
                }
                var request = URLRequest(url: url)
                if let apiKey = try credentialStore.apiKey(for: profile.id) {
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                }
                let (data, response) = try await session.data(for: request)
                try Self.throwWithServerMessage(data: data, response: response)
                do {
                    return try parseTokenLimitListResponse(data)
                } catch {
                    throw OmniRouteError.unknown(description: "Réponse de limites de jetons inattendue : \(error)")
                }
            } catch {
                let mapped = Self.mapNetworkingError(error)
                guard retryPolicy.shouldRetry(attempt: attempt, error: mapped) else { throw mapped }
                try await Task.sleep(for: .seconds(retryPolicy.delay(forAttempt: attempt)))
                attempt += 1
            }
        }
    }

    public func setTokenLimit(_ request: SetTokenLimitRequest) async throws {
        try await adminMutateNoContent(path: "api/usage/token-limits", method: "POST", body: request)
    }

    public func deleteTokenLimit(id: String) async throws {
        var attempt = 1
        while true {
            do {
                guard var components = URLComponents(
                    url: managementBaseURL.appendingPathComponent("api/usage/token-limits"),
                    resolvingAgainstBaseURL: false
                ) else {
                    throw OmniRouteError.unknown(description: "URL de limites de jetons invalide")
                }
                components.queryItems = [URLQueryItem(name: "id", value: id)]
                guard let url = components.url else {
                    throw OmniRouteError.unknown(description: "URL de limites de jetons invalide")
                }
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                if let apiKey = try credentialStore.apiKey(for: profile.id) {
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                }
                let (data, response) = try await session.data(for: request)
                try Self.throwWithServerMessage(data: data, response: response)
                return
            } catch {
                let mapped = Self.mapNetworkingError(error)
                guard retryPolicy.shouldRetry(attempt: attempt, error: mapped) else { throw mapped }
                try await Task.sleep(for: .seconds(retryPolicy.delay(forAttempt: attempt)))
                attempt += 1
            }
        }
    }

    // MARK: Shared helpers

    private func adminGET<T>(path: String, parse: @escaping (Data) throws -> T) async throws -> T {
        var attempt = 1
        while true {
            do {
                let request = try authorizedManagementRequest(path: path)
                let (data, response) = try await session.data(for: request)
                try Self.throwWithServerMessage(data: data, response: response)
                do {
                    return try parse(data)
                } catch {
                    throw OmniRouteError.unknown(description: "Réponse inattendue pour \(path) : \(error)")
                }
            } catch {
                let mapped = Self.mapNetworkingError(error)
                guard retryPolicy.shouldRetry(attempt: attempt, error: mapped) else { throw mapped }
                try await Task.sleep(for: .seconds(retryPolicy.delay(forAttempt: attempt)))
                attempt += 1
            }
        }
    }

    private func adminMutate<Body: Encodable, T>(
        path: String,
        method: String,
        body: Body?,
        parse: @escaping (Data) throws -> T
    ) async throws -> T {
        var attempt = 1
        while true {
            do {
                var request = try authorizedManagementRequest(path: path)
                request.httpMethod = method
                if let body {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(body)
                }
                let (data, response) = try await session.data(for: request)
                try Self.throwWithServerMessage(data: data, response: response)
                do {
                    return try parse(data)
                } catch {
                    throw OmniRouteError.unknown(description: "Réponse inattendue pour \(path) : \(error)")
                }
            } catch {
                let mapped = Self.mapNetworkingError(error)
                guard retryPolicy.shouldRetry(attempt: attempt, error: mapped) else { throw mapped }
                try await Task.sleep(for: .seconds(retryPolicy.delay(forAttempt: attempt)))
                attempt += 1
            }
        }
    }

    private func adminMutateNoContent<Body: Encodable>(path: String, method: String, body: Body? = Optional<String>.none) async throws {
        var attempt = 1
        while true {
            do {
                var request = try authorizedManagementRequest(path: path)
                request.httpMethod = method
                if let body {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(body)
                }
                let (data, response) = try await session.data(for: request)
                try Self.throwWithServerMessage(data: data, response: response)
                return
            } catch {
                let mapped = Self.mapNetworkingError(error)
                guard retryPolicy.shouldRetry(attempt: attempt, error: mapped) else { throw mapped }
                try await Task.sleep(for: .seconds(retryPolicy.delay(forAttempt: attempt)))
                attempt += 1
            }
        }
    }

    /// Confirmed empirically: every error this server returns uses
    /// `{"error":{"message":...}}`. Surfacing that real message (instead of
    /// the generic HTTP-status mapping the rest of the app uses) matters
    /// most here, where request bodies are best-effort guesses or the
    /// response shape isn't documented — a wrong guess needs to be visibly
    /// wrong, not silently generic.
    private static func throwWithServerMessage(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OmniRouteError.invalidResponse(statusCode: -1)
        }
        guard !(200..<300).contains(http.statusCode) else { return }
        if http.statusCode == 401 || http.statusCode == 403 {
            if let envelope = try? JSONDecoder().decode(AdminServerErrorEnvelope.self, from: data) {
                throw OmniRouteError.unknown(description: envelope.error.message)
            }
            throw OmniRouteError.authenticationFailed
        }
        if http.statusCode == 429 {
            throw OmniRouteError.rateLimited(retryAfterSeconds: http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init))
        }
        if let envelope = try? JSONDecoder().decode(AdminServerErrorEnvelope.self, from: data) {
            throw OmniRouteError.unknown(description: envelope.error.message)
        }
        throw OmniRouteError.invalidResponse(statusCode: http.statusCode)
    }
}
