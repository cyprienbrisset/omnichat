import Foundation

extension OmniRouteClient: MediaGenerating {
    public func generateImage(_ request: MediaGenerationRequest) async throws -> MediaGenerationResult {
        try await performMediaGeneration(request, path: "images/generations", defaultContentType: "image/png")
    }

    public func generateVideo(_ request: MediaGenerationRequest) async throws -> MediaGenerationResult {
        try await performMediaGeneration(request, path: "videos/generations", defaultContentType: "video/mp4")
    }

    public func generateMusic(_ request: MediaGenerationRequest) async throws -> MediaGenerationResult {
        try await performMediaGeneration(request, path: "music/generations", defaultContentType: "audio/mpeg")
    }

    public func synthesizeSpeech(_ request: SpeechRequest) async throws -> MediaGenerationResult {
        var attempt = 1
        while true {
            do {
                var urlRequest = try authorizedRequest(path: "audio/speech")
                urlRequest.httpMethod = "POST"
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.httpBody = try JSONEncoder().encode(request)

                let (data, response) = try await session.data(for: urlRequest)
                let http = try Self.requireSuccess(response)
                let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "audio/mpeg"
                return .inlineData(data, contentType: contentType)
            } catch {
                let mapped = Self.mapNetworkingError(error)
                guard retryPolicy.shouldRetry(attempt: attempt, error: mapped) else { throw mapped }
                try await Task.sleep(for: .seconds(retryPolicy.delay(forAttempt: attempt)))
                attempt += 1
            }
        }
    }

    private func performMediaGeneration(
        _ request: MediaGenerationRequest,
        path: String,
        defaultContentType: String
    ) async throws -> MediaGenerationResult {
        var attempt = 1
        while true {
            do {
                var urlRequest = try authorizedRequest(path: path)
                urlRequest.httpMethod = "POST"
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.httpBody = try JSONEncoder().encode(request)

                let (data, response) = try await session.data(for: urlRequest)
                _ = try Self.requireSuccess(response)
                do {
                    return try parseMediaGenerationResponse(data, defaultContentType: defaultContentType)
                } catch {
                    throw OmniRouteError.unknown(description: "Réponse média invalide: \(error)")
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
