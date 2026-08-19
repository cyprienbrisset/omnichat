import XCTest
@testable import OmniRouteKit

/// `URLSession` can deliver a POST body via `httpBodyStream` instead of
/// `httpBody` once a request has gone through a real session task.
private func capturedBodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4096
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: bufferSize)
        if read > 0 { data.append(buffer, count: read) } else { break }
    }
    return data
}

final class OmniRouteClientTranscriptionTests: XCTestCase {
    func test_transcribeAudio_success_decodesDocumentedResponseShape() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        var capturedContentType: String?
        var capturedBody: Data?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            capturedContentType = request.value(forHTTPHeaderField: "Content-Type")
            capturedBody = capturedBodyData(from: request)
            let json = #"{"text":"Bonjour, ceci est un test.","task":"transcribe","language":"fr","duration":3.2}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let result = try await client.transcribeAudio(
            fileData: Data("fake-audio-bytes".utf8),
            fileName: "memo.mp3",
            model: "deepgram/nova-3"
        )

        XCTAssertEqual(result.text, "Bonjour, ceci est un test.")
        XCTAssertEqual(result.language, "fr")
        XCTAssertEqual(result.duration, 3.2)
        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/v1/audio/transcriptions"))
        XCTAssertTrue(capturedContentType?.hasPrefix("multipart/form-data; boundary=") ?? false)
        let bodyString = capturedBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
        XCTAssertTrue(bodyString.contains("name=\"model\""))
        XCTAssertTrue(bodyString.contains("deepgram/nova-3"))
        XCTAssertTrue(bodyString.contains("name=\"file\"; filename=\"memo.mp3\""))
        XCTAssertTrue(bodyString.contains("fake-audio-bytes"))
    }

    func test_transcribeAudio_404_throwsInvalidResponse() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let client = OmniRouteClient(
            profile: profile, credentialStore: store, session: makeMockSession(),
            retryPolicy: RetryPolicy(maxAttempts: 1)
        )

        do {
            _ = try await client.transcribeAudio(fileData: Data(), fileName: "x.mp3", model: "broken/model")
            XCTFail("expected invalidResponse")
        } catch OmniRouteError.invalidResponse(404) {
            // expected
        }
    }

    func test_listTranscriptionModels_filtersByAudioTranscriptionSubtype() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        MockURLProtocol.requestHandler = { request in
            let json = #"""
            {"data":[
                {"id":"deepgram/nova-3","object":"model","owned_by":"deepgram","type":"audio","subtype":"transcription"},
                {"id":"openai/tts-1","object":"model","owned_by":"openai","type":"audio","subtype":"speech"},
                {"id":"openai/gpt-4o","object":"model","owned_by":"openai"}
            ]}
            """#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let models = try await client.listTranscriptionModels()

        XCTAssertEqual(models.map(\.id), ["deepgram/nova-3"])
    }
}
