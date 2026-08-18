import Foundation
import SwiftData
import OmniRouteKit

@Observable
final class AppEnvironment {
    var activeProfile: EndpointProfile
    let credentialStore: CredentialStore

    init(activeProfile: EndpointProfile = .defaultLocal, credentialStore: CredentialStore = KeychainCredentialStore()) {
        self.activeProfile = activeProfile
        self.credentialStore = credentialStore
    }

    func loadPersistedProfile(from context: ModelContext) {
        guard let stored = try? context.fetch(FetchDescriptor<StoredEndpointProfile>()).first,
              let baseURL = URL(string: stored.baseURLString) else {
            return
        }
        activeProfile = EndpointProfile(id: stored.profileID, name: stored.name, baseURL: baseURL)
    }

    func persistActiveProfile(baseURL: URL, apiKey: String, context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<StoredEndpointProfile>()).first
        let profileID = existing?.profileID ?? activeProfile.id

        if let existing {
            existing.baseURLString = baseURL.absoluteString
        } else {
            context.insert(StoredEndpointProfile(profileID: profileID, name: "Défaut", baseURLString: baseURL.absoluteString))
        }
        try context.save()

        try credentialStore.setAPIKey(apiKey, for: profileID)
        activeProfile = EndpointProfile(id: profileID, name: "Défaut", baseURL: baseURL)
    }
}
