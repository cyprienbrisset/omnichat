import XCTest
@testable import OmniRouteKit

final class OmniRouteClientModelsTests: XCTestCase {
    func test_listModels_decodesResponseBody() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        try store.setAPIKey("sk-test", for: profile.id)
        let json = #"{"data":[{"id":"claude-sonnet-5","owned_by":"anthropic"}]}"#.data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())
        let models = try await client.listModels()
        XCTAssertEqual(models, [ModelInfo(id: "claude-sonnet-5", ownedBy: "anthropic")])
    }

    func test_listModels_401_throwsAuthenticationFailed() async throws {
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
            _ = try await client.listModels()
            XCTFail("expected authenticationFailed")
        } catch OmniRouteError.authenticationFailed {
            // expected
        }
    }
}
