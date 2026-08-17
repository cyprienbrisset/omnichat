import Foundation
import OmniRouteKit

@Observable
final class AppEnvironment {
    var activeProfile: EndpointProfile
    let credentialStore: CredentialStore

    init(activeProfile: EndpointProfile = .defaultLocal, credentialStore: CredentialStore = KeychainCredentialStore()) {
        self.activeProfile = activeProfile
        self.credentialStore = credentialStore
    }
}
