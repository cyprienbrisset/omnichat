import Foundation

extension OmniRouteClient: EmbeddingGenerating {
    /// Real embedding vectors from `POST /v1/embeddings` — same plain
    /// bearer-key auth as chat, no management scope needed. Used to index
    /// conversation passages and to embed a search query against them.
    public func createEmbedding(model: String, input: String) async throws -> [Double] {
        var attempt = 1
        while true {
            do {
                var request = try authorizedRequest(path: "embeddings")
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(EmbeddingRequest(model: model, input: input))

                let (data, response) = try await session.data(for: request)
                _ = try Self.requireSuccess(response)
                do {
                    let decoded = try JSONDecoder().decode(EmbeddingListResponse.self, from: data)
                    guard let vector = decoded.data.first else {
                        throw OmniRouteError.unknown(description: "Réponse d'embedding vide")
                    }
                    return vector.embedding
                } catch let error as OmniRouteError {
                    throw error
                } catch {
                    throw OmniRouteError.unknown(description: "Réponse d'embedding inattendue : \(error)")
                }
            } catch {
                let mapped = Self.mapNetworkingError(error)
                guard retryPolicy.shouldRetry(attempt: attempt, error: mapped) else { throw mapped }
                try await Task.sleep(for: .seconds(retryPolicy.delay(forAttempt: attempt)))
                attempt += 1
            }
        }
    }

    /// Real catalog of embedding-capable models from `GET /v1/embeddings` —
    /// mirrors `listModels()` so indexing never guesses a hardcoded model id
    /// that might not exist on the connected server.
    public func listEmbeddingModels() async throws -> [ModelInfo] {
        var attempt = 1
        while true {
            do {
                let request = try authorizedRequest(path: "embeddings")
                let (data, response) = try await session.data(for: request)
                _ = try Self.requireSuccess(response)
                return try JSONDecoder().decode(ModelListResponse.self, from: data).data
            } catch {
                let mapped = Self.mapNetworkingError(error)
                guard retryPolicy.shouldRetry(attempt: attempt, error: mapped) else { throw mapped }
                try await Task.sleep(for: .seconds(retryPolicy.delay(forAttempt: attempt)))
                attempt += 1
            }
        }
    }
}
