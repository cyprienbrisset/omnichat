import XCTest
import SwiftData
import OmniRouteKit
@testable import OmniChat

final class AppEnvironmentPersistenceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Conversation.self, Message.self, StoredEndpointProfile.self, SearchPassage.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    func test_persistActiveProfile_reusesSameProfileIDAcrossSaves() throws {
        let context = try makeContext()
        let environment = AppEnvironment(credentialStore: InMemoryCredentialStore())
        let url = URL(string: "https://example.omniroute.online/v1")!

        try environment.persistActiveProfile(baseURL: url, apiKey: "sk-test", context: context)
        let firstProfileID = environment.activeProfile.id

        try environment.persistActiveProfile(baseURL: url, apiKey: "sk-test-2", context: context)

        XCTAssertEqual(environment.activeProfile.id, firstProfileID)
        let stored = try context.fetch(FetchDescriptor<StoredEndpointProfile>())
        XCTAssertEqual(stored.count, 1, "must not create a duplicate StoredEndpointProfile on a second save")
    }

    func test_loadPersistedProfile_restoresSavedEndpoint() throws {
        let context = try makeContext()
        let saver = AppEnvironment(credentialStore: InMemoryCredentialStore())
        let url = URL(string: "https://example.omniroute.online/v1")!
        try saver.persistActiveProfile(baseURL: url, apiKey: "sk-test", context: context)

        let loader = AppEnvironment(credentialStore: InMemoryCredentialStore())
        loader.loadPersistedProfile(from: context)

        XCTAssertEqual(loader.activeProfile.id, saver.activeProfile.id)
        XCTAssertEqual(loader.activeProfile.baseURL, url)
    }
}
