import XCTest
@testable import OmniRouteKit

final class CredentialStoreTests: XCTestCase {
    func test_setThenGet_returnsStoredKey() throws {
        let store = InMemoryCredentialStore()
        let id = UUID()
        try store.setAPIKey("sk-test-123", for: id)
        XCTAssertEqual(try store.apiKey(for: id), "sk-test-123")
    }

    func test_get_beforeSet_returnsNil() throws {
        let store = InMemoryCredentialStore()
        XCTAssertNil(try store.apiKey(for: UUID()))
    }

    func test_defaultLocalProfile_pointsAtLocalhost20128() {
        XCTAssertEqual(EndpointProfile.defaultLocal.baseURL.absoluteString, "http://localhost:20128/v1")
    }
}
