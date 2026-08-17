import Foundation

public protocol CredentialStore: Sendable {
    func apiKey(for profileID: UUID) throws -> String?
    func setAPIKey(_ apiKey: String, for profileID: UUID) throws
}

public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UUID: String] = [:]

    public init() {}

    public func apiKey(for profileID: UUID) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[profileID]
    }

    public func setAPIKey(_ apiKey: String, for profileID: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        storage[profileID] = apiKey
    }
}
