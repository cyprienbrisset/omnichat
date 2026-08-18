import XCTest
@testable import OmniRouteKit

final class OmniRouteClientMonitoringTests: XCTestCase {
    func test_fetchMonitoringHealth_success_decodesNestedProviderSummary() async throws {
        let profile = EndpointProfile(id: UUID(), name: "Test", baseURL: URL(string: "https://omniroute.online/v1")!)
        let store = InMemoryCredentialStore()
        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            // Shape confirmed against a live OmniRoute 3.8.49 instance — the
            // counts live under `providerSummary`, not top-level, alongside a
            // much larger process-health payload this app ignores.
            let json = #"""
            {"status":"healthy","version":"3.8.49","providerSummary":{"catalogCount":340,"configuredCount":210,"activeCount":198,"monitoredCount":205}}
            """#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
        let client = OmniRouteClient(profile: profile, credentialStore: store, session: makeMockSession())

        let health = try await client.fetchMonitoringHealth()

        XCTAssertEqual(health.catalogCount, 340)
        XCTAssertEqual(health.activeCount, 198)
        XCTAssertEqual(capturedURL, URL(string: "https://omniroute.online/api/monitoring/health"))
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
