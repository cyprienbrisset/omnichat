import XCTest
@testable import OmniRouteKit

final class OmniRouteClientEmbeddingsTests: XCTestCase {
    func test_createEmbedding_success_returnsFirstVector() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        var capturedMethod: String?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            capturedMethod = request.httpMethod
            let json = #"{"data":[{"embedding":[0.1,0.2,0.3],"index":0}]}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let vector = try await client.createEmbedding(model: "test-embed", input: "hello")

        XCTAssertEqual(vector, [0.1, 0.2, 0.3])
        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/v1/embeddings"))
        XCTAssertEqual(capturedMethod, "POST")
    }

    func test_createEmbedding_emptyData_throwsUnknown() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"data":[]}"#.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        do {
            _ = try await client.createEmbedding(model: "test-embed", input: "hello")
            XCTFail("expected unknown error")
        } catch OmniRouteError.unknown {
            // expected
        }
    }

    func test_listEmbeddingModels_success_decodesCatalog() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let json = #"{"object":"list","data":[{"id":"nebius/Qwen/Qwen3-Embedding-8B","object":"model","owned_by":"nebius"}]}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let models = try await client.listEmbeddingModels()

        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].id, "nebius/Qwen/Qwen3-Embedding-8B")
        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/v1/embeddings"))
    }
}
