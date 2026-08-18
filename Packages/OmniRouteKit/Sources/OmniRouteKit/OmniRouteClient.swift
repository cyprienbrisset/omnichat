import Foundation

public actor OmniRouteClient {
    private nonisolated let profile: EndpointProfile
    private nonisolated let credentialStore: CredentialStore
    nonisolated let session: URLSession
    nonisolated let retryPolicy: RetryPolicy

    public init(
        profile: EndpointProfile,
        credentialStore: CredentialStore,
        session: URLSession = .shared,
        retryPolicy: RetryPolicy = RetryPolicy()
    ) {
        self.profile = profile
        self.credentialStore = credentialStore
        self.session = session
        self.retryPolicy = retryPolicy
    }

    nonisolated func authorizedRequest(path: String) throws -> URLRequest {
        var request = URLRequest(url: profile.baseURL.appendingPathComponent(path))
        if let apiKey = try credentialStore.apiKey(for: profile.id) {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    public func listModels() async throws -> [ModelInfo] {
        var attempt = 1
        while true {
            do {
                let request = try authorizedRequest(path: "models")
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

    static func requireSuccess(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw OmniRouteError.invalidResponse(statusCode: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OmniRouteError.from(
                httpStatusCode: http.statusCode,
                retryAfterHeader: http.value(forHTTPHeaderField: "Retry-After")
            )
        }
        return http
    }

    static func mapNetworkingError(_ error: Error) -> OmniRouteError {
        if let omni = error as? OmniRouteError { return omni }
        if let urlError = error as? URLError { return .from(urlError: urlError) }
        return .unknown(description: "\(error)")
    }
}

public protocol ChatCompleting: Sendable {
    func streamChatCompletion(_ request: ChatCompletionRequest) -> AsyncThrowingStream<ChatDelta, Error>
}

extension OmniRouteClient: ChatCompleting {
    public nonisolated func streamChatCompletion(_ request: ChatCompletionRequest) -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = try authorizedRequest(path: "chat/completions")
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.httpBody = try JSONEncoder().encode(request)

                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    let http = try Self.requireSuccess(response)
                    if let telemetry = RequestTelemetry.parse(from: http) {
                        continuation.yield(ChatDelta(content: "", isFinal: false, telemetry: telemetry))
                    }

                    var receivedFinal = false
                    for try await line in bytes.lines {
                        guard let delta = SSELineParser.parse(line: line) else { continue }
                        if delta.isFinal {
                            receivedFinal = true
                            break
                        }
                        continuation.yield(delta)
                    }
                    guard receivedFinal else { throw OmniRouteError.streamInterrupted }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapNetworkingError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
