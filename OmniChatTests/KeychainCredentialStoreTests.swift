import XCTest
import Security
@testable import OmniChat
import OmniRouteKit

final class KeychainCredentialStoreTests: XCTestCase {
    private var service: String!

    override func setUpWithError() throws {
        service = "online.omniroute.omnichat.tests.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service as Any
        ]
        SecItemDelete(query as CFDictionary)
    }

    func test_setThenGet_roundTripsThroughRealKeychain() throws {
        let store = KeychainCredentialStore(service: service)
        let profileID = UUID()
        try store.setAPIKey("sk-test-abc", for: profileID)
        XCTAssertEqual(try store.apiKey(for: profileID), "sk-test-abc")
    }

    func test_update_overwritesExistingKey() throws {
        let store = KeychainCredentialStore(service: service)
        let profileID = UUID()
        try store.setAPIKey("sk-first", for: profileID)
        try store.setAPIKey("sk-second", for: profileID)
        XCTAssertEqual(try store.apiKey(for: profileID), "sk-second")
    }

    func test_get_unknownProfile_returnsNil() throws {
        let store = KeychainCredentialStore(service: service)
        XCTAssertNil(try store.apiKey(for: UUID()))
    }
}
