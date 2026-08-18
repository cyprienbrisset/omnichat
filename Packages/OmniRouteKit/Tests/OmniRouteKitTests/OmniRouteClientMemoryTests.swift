import XCTest
@testable import OmniRouteKit

final class OmniRouteClientMemoryTests: XCTestCase {
    func test_listMemories_success_parsesBareArray() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let json = #"[{"id":"m1","content":"x","key":null,"type":"FACTUAL","sessionId":null,"createdAt":null}]"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let memories = try await client.listMemories()

        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories[0].id, "m1")
        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/api/memory"))
    }

    func test_listMemories_401_throwsAuthenticationFailed() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        do {
            _ = try await client.listMemories()
            XCTFail("expected authenticationFailed")
        } catch OmniRouteError.authenticationFailed {
            // expected
        }
    }

    func test_listMemories_unrecognizedShape_throwsUnknown() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"nope":true}"#.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        do {
            _ = try await client.listMemories()
            XCTFail("expected unknown parse error")
        } catch OmniRouteError.unknown {
            // expected
        }
    }

    func test_deleteMemory_success_sendsDeleteToCorrectPath() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        var capturedMethod: String?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            capturedMethod = request.httpMethod
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        try await client.deleteMemory(id: "m1")

        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/api/memory/m1"))
        XCTAssertEqual(capturedMethod, "DELETE")
    }
}
