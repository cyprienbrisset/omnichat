import XCTest
@testable import OmniRouteKit

final class OmniRouteErrorMappingTests: XCTestCase {
    func test_401_mapsToAuthenticationFailed() {
        XCTAssertEqual(OmniRouteError.from(httpStatusCode: 401, retryAfterHeader: nil), .authenticationFailed)
    }

    func test_429_mapsToRateLimitedWithRetryAfter() {
        XCTAssertEqual(
            OmniRouteError.from(httpStatusCode: 429, retryAfterHeader: "12"),
            .rateLimited(retryAfterSeconds: 12)
        )
    }

    func test_500_mapsToInvalidResponse() {
        XCTAssertEqual(OmniRouteError.from(httpStatusCode: 500, retryAfterHeader: nil), .invalidResponse(statusCode: 500))
    }

    func test_urlError_mapsToNetwork() {
        let urlError = URLError(.timedOut)
        XCTAssertEqual(OmniRouteError.from(urlError: urlError), .network(description: urlError.localizedDescription))
    }
}
