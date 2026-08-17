import Foundation
import Security
import OmniRouteKit

enum KeychainError: Error {
    case invalidData
    case osStatus(OSStatus)
}

final class KeychainCredentialStore: CredentialStore, @unchecked Sendable {
    private let service: String

    init(service: String = "online.omniroute.omnichat") {
        self.service = service
    }

    func apiKey(for profileID: UUID) throws -> String? {
        var query = baseQuery(for: profileID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.osStatus(status)
        }
    }

    func setAPIKey(_ apiKey: String, for profileID: UUID) throws {
        let data = Data(apiKey.utf8)
        let query = baseQuery(for: profileID)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.osStatus(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.osStatus(updateStatus)
        }
    }

    private func baseQuery(for profileID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString
        ]
    }
}
