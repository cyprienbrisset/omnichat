import XCTest
@testable import OmniRouteKit

final class OmniRouteClientManagementCapabilityTests: XCTestCase {
    func test_hasManagementAccess_targetsSiblingApiPath_notNestedUnderV1() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[]".utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let hasAccess = await client.hasManagementAccess()

        XCTAssertTrue(hasAccess)
        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/api/memory"))
    }

    func test_hasManagementAccess_401_returnsFalse() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let hasAccess = await client.hasManagementAccess()

        XCTAssertFalse(hasAccess)
    }

    func test_hasManagementAccess_networkFailure_returnsFalseWithoutThrowing() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let hasAccess = await client.hasManagementAccess()

        XCTAssertFalse(hasAccess)
    }
}
