import XCTest
@testable import OmniRouteKit

/// `URLSession` can deliver a POST body via `httpBodyStream` instead of
/// `httpBody` once a request has gone through a session task — this reads
/// whichever one is actually present.
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

final class OmniRouteClientAdminTests: XCTestCase {
    func test_listProviders_success_parsesBareArray() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let json = #"[{"id":"p1","name":"Fireworks"}]"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let providers = try await client.listProviders()

        XCTAssertEqual(providers.map(\.id), ["p1"])
        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/api/providers"))
    }

    func test_testProvider_success_sendsPostToCorrectPath() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        var capturedMethod: String?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            capturedMethod = request.httpMethod
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"ok":true}"#.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let result = try await client.testProvider(id: "p1")

        XCTAssertEqual(result.fields["ok"], .bool(true))
        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/api/providers/p1/test"))
        XCTAssertEqual(capturedMethod, "POST")
    }

    func test_deleteProvider_success_sendsDeleteToCorrectPath() async throws {
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

        try await client.deleteProvider(id: "p1")

        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/api/providers/p1"))
        XCTAssertEqual(capturedMethod, "DELETE")
    }

    func test_createProvider_encodesBestEffortBody() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedBody: [String: Any]?
        MockURLProtocol.requestHandler = { request in
            if let bodyData = capturedBodyData(from: request) {
                capturedBody = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"id":"p1"}"#.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        _ = try await client.createProvider(name: "My Fireworks", providerType: "fireworks", apiKey: "sk-test")

        XCTAssertEqual(capturedBody?["name"] as? String, "My Fireworks")
        XCTAssertEqual(capturedBody?["provider"] as? String, "fireworks")
        XCTAssertEqual(capturedBody?["apiKey"] as? String, "sk-test")
    }

    func test_createProvider_400WithServerMessage_surfacesRealMessage() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        MockURLProtocol.requestHandler = { request in
            let json = #"{"error":{"message":"providerType: Invalid enum value. Expected 'openai' | 'fireworks', received 'nope'"}}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        do {
            _ = try await client.createProvider(name: "x", providerType: "nope", apiKey: "y")
            XCTFail("expected the real server message to surface")
        } catch OmniRouteError.unknown(let description) {
            XCTAssertTrue(description.contains("Invalid enum value"))
        }
    }

    func test_listBudgets_success_decodesDocumentedSchema() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let json = #"[{"apiKeyId":"key-1","dailyLimitUsd":5.0,"weeklyLimitUsd":null,"monthlyLimitUsd":null,"warningThreshold":null,"resetInterval":"daily"}]"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let budgets = try await client.listBudgets()

        XCTAssertEqual(budgets.map(\.apiKeyId), ["key-1"])
        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/api/usage/budget"))
    }

    func test_setBudget_success_sendsDocumentedBody() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        var capturedBody: [String: Any]?
        MockURLProtocol.requestHandler = { request in
            if let bodyData = capturedBodyData(from: request) {
                capturedBody = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        try await client.setBudget(SetBudgetRequest(apiKeyId: "key-1", monthlyLimitUsd: 100))

        XCTAssertEqual(capturedBody?["apiKeyId"] as? String, "key-1")
        XCTAssertEqual(capturedBody?["monthlyLimitUsd"] as? Double, 100)
    }

    func test_listTokenLimits_success_sendsApiKeyIdQueryParam() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let json = #"[{"id":"tl-1","apiKeyId":"key-1","scopeType":"global","scopeValue":null,"tokenLimit":500,"resetInterval":"monthly","enabled":true,"tokensUsed":10,"remaining":490,"nextResetAt":null}]"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let limits = try await client.listTokenLimits(apiKeyId: "key-1")

        XCTAssertEqual(limits.map(\.id), ["tl-1"])
        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/api/usage/token-limits?apiKeyId=key-1"))
    }

    func test_deleteTokenLimit_success_sendsIdQueryParam() async throws {
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

        try await client.deleteTokenLimit(id: "tl-abc")

        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/api/usage/token-limits?id=tl-abc"))
        XCTAssertEqual(capturedMethod, "DELETE")
    }

    func test_listProviders_401NoEnvelope_throwsAuthenticationFailed() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        do {
            _ = try await client.listProviders()
            XCTFail("expected authenticationFailed")
        } catch OmniRouteError.authenticationFailed {
            // expected
        }
    }

    func test_fetchRateLimitStatus_success_parsesRawSnapshotFromCorrectPath() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let json = #"{"remaining":42,"limit":100,"resetAt":"2026-09-01T00:00:00Z"}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let status = try await client.fetchRateLimitStatus()

        XCTAssertEqual(status.fields["remaining"], .number(42))
        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/api/rate-limits"))
    }

    func test_listACPAgents_success_decodesDocumentedResponseShape() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let json = #"""
            {"agents":[{"id":"claude","name":"Claude Code CLI","binary":"claude","version":"1.0.45","installed":true,"protocol":"stdio","providerAlias":"claude","isCustom":false}],"cacheTtlMs":60000,"cacheAge":1234}
            """#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let result = try await client.listACPAgents()

        XCTAssertEqual(result.agents.map(\.id), ["claude"])
        XCTAssertEqual(result.agents.first?.installed, true)
        XCTAssertEqual(result.cacheTtlMs, 60000)
        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/api/acp/agents"))
    }

    func test_listPolicies_success_parsesRawSnapshotListFromCorrectPath() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let json = #"[{"id":"p1","name":"No PII"}]"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let policies = try await client.listPolicies()

        XCTAssertEqual(policies.map(\.id), ["p1"])
        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/api/policies"))
    }

    func test_fetchProxySettings_success_parsesRawSnapshotFromCorrectPath() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let json = #"{"enabled":false}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let settings = try await client.fetchProxySettings()

        XCTAssertEqual(settings.fields["enabled"], .bool(false))
        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/api/settings/proxy"))
    }

    func test_fetchIPFilterSettings_success_parsesRawSnapshotFromCorrectPath() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let json = #"{"mode":"allowlist"}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let settings = try await client.fetchIPFilterSettings()

        XCTAssertEqual(settings.fields["mode"], .string("allowlist"))
        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/api/settings/ip-filter"))
    }

    func test_listModelLatencyStats_success_parsesRawSnapshotListFromCorrectPath() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            let json = #"[{"provider":"openai","model":"gpt-4o","avgMs":312,"successRate":0.994}]"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let stats = try await client.listModelLatencyStats()

        XCTAssertEqual(stats.first?.fields["avgMs"], .number(312))
        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/api/usage/model-latency-stats"))
    }
}
