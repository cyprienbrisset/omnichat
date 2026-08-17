import XCTest
@testable import OmniRouteKit

final class OmniRouteKitTests: XCTestCase {
    func test_apiVersion_isV1() {
        XCTAssertEqual(OmniRouteKitInfo.apiVersion, "v1")
    }
}
