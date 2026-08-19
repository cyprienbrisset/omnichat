import XCTest
@testable import OmniRouteKit

final class OmniRouteClientMonitoringTests: XCTestCase {
    func test_fetchMonitoringHealth_success_decodesRealShape() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            // Real shape, captured against a live OmniRoute 3.8.49 instance —
            // the counts live under `providerSummary`, not top-level,
            // alongside a much larger process-health payload this app mostly
            // ignores (memory, sessions, quota monitor, dedup, crypto…).
            let json = """
            {"status":"healthy","version":"3.8.49","uptime":60210.49,"activeConnections":35,\
            "circuitBreakers":{"open":0,"halfOpen":0,"degraded":0,"closed":1,"total":1},\
            "providerBreakers":[{"provider":"gemini-web","state":"CLOSED","failureCount":1,\
            "lastFailure":"2026-08-19T09:33:52.714Z","retryAfterMs":0}],\
            "providerSummary":{"catalogCount":340,"configuredCount":210,"activeCount":198,"monitoredCount":205},\
            "credentialHealth":{"total":31,"healthy":31,"failed":0,"unknown":0,"stale":0}}
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let health = try await client.fetchMonitoringHealth()

        XCTAssertEqual(health.catalogCount, 340)
        XCTAssertEqual(health.activeCount, 198)
        XCTAssertEqual(health.version, "3.8.49")
        XCTAssertEqual(health.uptimeSeconds, 60210.49)
        XCTAssertEqual(health.activeConnections, 35)
        XCTAssertEqual(health.credentialHealth.healthy, 31)
        XCTAssertEqual(health.circuitBreakers.closed, 1)
        XCTAssertEqual(health.providerBreakers.first?.provider, "gemini-web")
        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/api/monitoring/health"))
    }

    func test_fetchMonitoringHealth_missingOptionalFields_fallsBackToDefaults() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        MockURLProtocol.requestHandler = { request in
            let json = #"{"providerSummary":{"catalogCount":1,"configuredCount":1,"activeCount":1,"monitoredCount":1}}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let health = try await client.fetchMonitoringHealth()

        XCTAssertEqual(health.version, "?")
        XCTAssertEqual(health.credentialHealth, .empty)
        XCTAssertTrue(health.providerBreakers.isEmpty)
    }

    func test_fetchMonitoringHealth_401_throwsAuthenticationFailed() async throws {
        let profile = EndpointProfile.defaultLocal
        let store = InMemoryCredentialStore()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        do {
            _ = try await client.fetchMonitoringHealth()
            XCTFail("expected authenticationFailed")
        } catch OmniRouteError.authenticationFailed {
            // expected
        }
    }
}
