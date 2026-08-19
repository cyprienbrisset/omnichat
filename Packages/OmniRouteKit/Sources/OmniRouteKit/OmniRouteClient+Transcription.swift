import Foundation

extension OmniRouteClient: AudioTranscribing {
    public func listTranscriptionModels() async throws -> [ModelInfo] {
        try await listModels().filter { $0.type == "audio" && $0.subtype == "transcription" }
    }

    public func transcribeAudio(fileData: Data, fileName: String, model: String) async throws -> TranscriptionResult {
        var attempt = 1
        while true {
            do {
                var urlRequest = try authorizedRequest(path: "audio/transcriptions")
                urlRequest.httpMethod = "POST"
                let boundary = "OmniChat-\(UUID().uuidString)"
                urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                urlRequest.httpBody = Self.multipartTranscriptionBody(
                    boundary: boundary,
                    model: model,
                    fileData: fileData,
                    fileName: fileName
                )

                let (data, response) = try await session.data(for: urlRequest)
                _ = try Self.requireSuccess(response)
                return try JSONDecoder().decode(TranscriptionResult.self, from: data)
            } catch {
                let mapped = Self.mapNetworkingError(error)
                guard retryPolicy.shouldRetry(attempt: attempt, error: mapped) else { throw mapped }
                try await Task.sleep(for: .seconds(retryPolicy.delay(forAttempt: attempt)))
                attempt += 1
            }
        }
    }

    /// `multipart/form-data` per the documented request
    /// (`-F "file=@recording.mp3" -F "model=deepgram/nova-3"`) — built by
    /// hand since `URLSession` has no built-in multipart encoder.
    private static func multipartTranscriptionBody(
        boundary: String,
        model: String,
        fileData: Data,
        fileName: String
    ) -> Data {
        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(model)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }
}
