import XCTest
@testable import OmniRouteKit

final class OmniRouteClientMCPTests: XCTestCase {
    func test_listMCPTools_success_parsesBareArray() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let json = #"[{"name":"web_search","description":null,"scopes":null,"phase":null,"auditLevel":null,"sourceEndpoints":null}]"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let tools = try await client.listMCPTools()

        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0].name, "web_search")
        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/api/mcp/tools"))
    }

    func test_listMCPTools_401_throwsAuthenticationFailed() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        do {
            _ = try await client.listMCPTools()
            XCTFail("expected authenticationFailed")
        } catch OmniRouteError.authenticationFailed {
            // expected
        }
    }

    func test_fetchMCPStatus_success_returnsRawSnapshot() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let json = #"{"online":true,"transport":"sse"}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let status = try await client.fetchMCPStatus()

        XCTAssertEqual(status.fields["online"], .bool(true))
        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/api/mcp/status"))
    }

    func test_fetchMCPAuditStats_success_returnsRawSnapshot() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let json = #"{"totalCalls":42}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let stats = try await client.fetchMCPAuditStats()

        XCTAssertEqual(stats.fields["totalCalls"], .number(42))
        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/api/mcp/audit/stats"))
    }

    func test_fetchMCPAudit_success_sendsLimitQueryParam() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let json = #"[{"tool":"web_search","success":true}]"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let entries = try await client.fetchMCPAudit(limit: 10)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].fields["tool"], .string("web_search"))
        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/api/mcp/audit?limit=10"))
    }

    /// Confirmed empirically against a live OmniRoute 3.8.49 instance: every
    /// `/api/mcp/*` route 403s with this exact envelope when reached from
    /// anywhere but localhost, regardless of the key's rights.
    func test_fetchMCPStatus_localOnly403_throwsDistinguishableError() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        MockURLProtocol.requestHandler = { request in
            let json = #"{"error":{"code":"LOCAL_ONLY","message":"This endpoint requires localhost access","correlation_id":"abc"}}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        do {
            _ = try await client.fetchMCPStatus()
            XCTFail("expected a LOCAL_ONLY-specific error")
        } catch OmniRouteError.unknown(let description) {
            XCTAssertTrue(description.localizedCaseInsensitiveContains("localhost"))
        }
    }

    func test_listMCPTools_localOnly403_throwsDistinguishableError() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        MockURLProtocol.requestHandler = { request in
            let json = #"{"error":{"code":"LOCAL_ONLY","message":"This endpoint requires localhost access","correlation_id":"abc"}}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        do {
            _ = try await client.listMCPTools()
            XCTFail("expected a LOCAL_ONLY-specific error")
        } catch OmniRouteError.unknown(let description) {
            XCTAssertTrue(description.localizedCaseInsensitiveContains("localhost"))
        }
    }
}
