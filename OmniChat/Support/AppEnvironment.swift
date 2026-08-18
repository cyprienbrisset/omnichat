import Foundation
import SwiftData
import OmniRouteKit

/// Whether the configured API key also carries management scope (`/api/*`),
/// beyond the plain chat scope every key has. Same key, checked capability —
/// never a second credential. `.unknown` until the first check completes.
enum ManagementAccessState: Equatable {
    case unknown
    case checking
    case available
    case unavailable
}

/// A real, measured snapshot of the connected server's catalog — never a
/// placeholder. `providerCount` is the number of distinct `owned_by` values
/// across `listModels()`, since `/v1/models` doesn't expose a proper
/// provider list without management access.
struct CatalogSummary: Equatable {
    let modelCount: Int
    let providerCount: Int
}

@Observable
final class AppEnvironment {
    var activeProfile: EndpointProfile
    let credentialStore: CredentialStore
    let diagnosticLogger: DiagnosticLogger
    private(set) var managementAccessState: ManagementAccessState = .unknown
    private(set) var catalogSummary: CatalogSummary?

    var themePreference: ThemePreference {
        didSet {
            UserDefaults.standard.set(themePreference.rawValue, forKey: Self.themePreferenceKey)
        }
    }

    private static let themePreferenceKey = "themePreference"

    init(
        activeProfile: EndpointProfile = .defaultLocal,
        credentialStore: CredentialStore = KeychainCredentialStore(),
        diagnosticLogger: DiagnosticLogger = AppEnvironment.makeDefaultDiagnosticLogger()
    ) {
        self.activeProfile = activeProfile
        self.credentialStore = credentialStore
        self.diagnosticLogger = diagnosticLogger
        self.themePreference = UserDefaults.standard.string(forKey: Self.themePreferenceKey)
            .flatMap(ThemePreference.init(rawValue:)) ?? .system
    }

    static func makeDefaultDiagnosticLogger() -> DiagnosticLogger {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = appSupport.appendingPathComponent("OmniChat", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return DiagnosticLogger(fileURL: directory.appendingPathComponent("diagnostics.json"))
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

        // Write the Keychain credential first so a failure here never leaves
        // `activeProfile` pointing at a URL with no matching stored key.
        if !apiKey.isEmpty {
            try credentialStore.setAPIKey(apiKey, for: profileID)
        }

        if let existing {
            existing.baseURLString = baseURL.absoluteString
        } else {
            context.insert(StoredEndpointProfile(profileID: profileID, name: "Défaut", baseURLString: baseURL.absoluteString))
        }
        try context.save()

        activeProfile = EndpointProfile(id: profileID, name: "Défaut", baseURL: baseURL)
    }

    /// Re-probes the active key's management scope against the server —
    /// call after launch and whenever the connection is (re)saved, since a
    /// new key or endpoint may carry different rights than the last one.
    @MainActor
    func refreshManagementAccess() async {
        managementAccessState = .checking
        let client = OmniRouteClient(profile: activeProfile, credentialStore: credentialStore)
        let hasAccess = await client.hasManagementAccess()
        managementAccessState = hasAccess ? .available : .unavailable
    }

    /// Re-fetches the real model catalog so the rail's summary label
    /// reflects the actually-connected server rather than nothing at all.
    /// Silently leaves `catalogSummary` as-is on failure — this is a
    /// decorative refresh, not something that should surface an error banner.
    @MainActor
    func refreshCatalogSummary() async {
        let client = OmniRouteClient(profile: activeProfile, credentialStore: credentialStore)
        guard let models = try? await client.listModels() else { return }
        let providerCount = Set(models.compactMap(\.ownedBy)).count
        catalogSummary = CatalogSummary(modelCount: models.count, providerCount: providerCount)
    }

    func updateCatalogSummary(modelCount: Int, providerCount: Int) {
        catalogSummary = CatalogSummary(modelCount: modelCount, providerCount: providerCount)
    }
}
