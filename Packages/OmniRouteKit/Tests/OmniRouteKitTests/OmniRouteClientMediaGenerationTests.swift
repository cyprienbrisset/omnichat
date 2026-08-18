import XCTest
@testable import OmniRouteKit

final class OmniRouteClientMediaGenerationTests: XCTestCase {
    func test_generateImage_success_returnsRemoteURL() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        let json = #"{"data":[{"url":"https://example.com/cat.png"}]}"#.data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())
        let result = try await client.generateImage(MediaGenerationRequest(model: "auto", prompt: "un chat"))
        XCTAssertEqual(result, .remoteURL(URL(string: "https://example.com/cat.png")!))
    }

    func test_generateVideo_success_returnsRemoteURL() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        let json = #"{"data":[{"url":"https://example.com/clip.mp4"}]}"#.data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())
        let result = try await client.generateVideo(MediaGenerationRequest(model: "auto", prompt: "un lever de soleil"))
        XCTAssertEqual(result, .remoteURL(URL(string: "https://example.com/clip.mp4")!))
    }

    func test_generateMusic_success_returnsRemoteURL() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        let json = #"{"data":[{"url":"https://example.com/song.mp3"}]}"#.data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())
        let result = try await client.generateMusic(MediaGenerationRequest(model: "auto", prompt: "une berceuse"))
        XCTAssertEqual(result, .remoteURL(URL(string: "https://example.com/song.mp3")!))
    }

    func test_generateImage_401_throwsAuthenticationFailed() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let client = OmniRouteClient(
            profile: profile, credentialStore: store, session: makeMockSession(),
            retryPolicy: RetryPolicy(maxAttempts: 1)
        )
        do {
            _ = try await client.generateImage(MediaGenerationRequest(model: "auto", prompt: "x"))
            XCTFail("expected authenticationFailed")
        } catch OmniRouteError.authenticationFailed {
            // expected
        }
    }
}
