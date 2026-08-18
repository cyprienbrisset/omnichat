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

    public func listImageModels() async throws -> [ModelInfo] {
        try await listMediaModels(path: "images/generations")
    }

    public func listVideoModels() async throws -> [ModelInfo] {
        try await listMediaModels(path: "videos/generations")
    }

    public func listMusicModels() async throws -> [ModelInfo] {
        try await listMediaModels(path: "music/generations")
    }

    /// `/v1/audio/speech` has no `GET` catalog of its own (confirmed: `405`
    /// live) — TTS-capable models are filtered out of the main `/v1/models`
    /// catalog instead, where they're tagged `type: "audio", subtype:
    /// "speech"` (distinct from `subtype: "transcription"`, which this app
    /// can't use for generation).
    public func listSpeechModels() async throws -> [ModelInfo] {
        try await listModels().filter { $0.type == "audio" && $0.subtype == "speech" }
    }

    private func listMediaModels(path: String) async throws -> [ModelInfo] {
        var attempt = 1
        while true {
            do {
                let request = try authorizedRequest(path: path)
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
