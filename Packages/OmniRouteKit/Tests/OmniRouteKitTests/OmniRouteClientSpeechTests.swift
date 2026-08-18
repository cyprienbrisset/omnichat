import XCTest
@testable import OmniRouteKit

final class OmniRouteClientSpeechTests: XCTestCase {
    func test_synthesizeSpeech_success_returnsInlineDataWithContentType() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        let audioBytes = Data("fake-mp3-bytes".utf8)
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "audio/mpeg"]
            )!
            return (response, audioBytes)
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())
        let result = try await client.synthesizeSpeech(SpeechRequest(model: "auto", input: "Bonjour"))
        XCTAssertEqual(result, .inlineData(audioBytes, contentType: "audio/mpeg"))
    }

    func test_synthesizeSpeech_429_throwsRateLimited() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 429, httpVersion: nil,
                headerFields: ["Retry-After": "5"]
            )!
            return (response, Data())
        }
        let client = OmniRouteClient(
            profile: profile, credentialStore: store, session: makeMockSession(),
            retryPolicy: RetryPolicy(maxAttempts: 1)
        )
        do {
            _ = try await client.synthesizeSpeech(SpeechRequest(model: "auto", input: "x"))
            XCTFail("expected rateLimited")
        } catch OmniRouteError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 5)
        }
    }
}
