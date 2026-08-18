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
    private(set) var monitoringHealth: MonitoringHealth?
    /// Media kinds this server actually has at least one real model for —
    /// starts empty (nothing shown) rather than assuming availability, so
    /// the composer never offers a generation mode that's guaranteed to
    /// fail with "no model configured".
    private(set) var availableMediaKinds: Set<MediaKind> = []
    /// Passages the user picked from local search (`RAGView`) to attach as
    /// context to their *next* outgoing message — one-shot, cleared by
    /// `ChatView` right after it reads them into the request.
    var pendingAttachedContext: [String] = []

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

    /// Real provider health counts for the sidebar indicator. Requires
    /// management scope — silently leaves `monitoringHealth` nil (never a
    /// fabricated count) when the key lacks rights or the call fails.
    @MainActor
    func refreshMonitoringHealth() async {
        guard managementAccessState == .available else { return }
        let client = OmniRouteClient(profile: activeProfile, credentialStore: credentialStore)
        monitoringHealth = try? await client.fetchMonitoringHealth()
    }

    /// Real per-kind availability, confirmed against each generation
    /// endpoint's own catalog (`listImageModels()` etc.) — never inferred
    /// from `/v1/models` alone, since a server can list e.g. embedding
    /// models without having any image provider configured. A failed or
    /// empty catalog for a kind simply means it stays out of the set;
    /// this never surfaces as an error banner.
    @MainActor
    func refreshAvailableMediaKinds() async {
        let client = OmniRouteClient(profile: activeProfile, credentialStore: credentialStore)
        async let imagesTask: [ModelInfo]? = try? client.listImageModels()
        async let videosTask: [ModelInfo]? = try? client.listVideoModels()
        async let musicTask: [ModelInfo]? = try? client.listMusicModels()
        async let speechTask: [ModelInfo]? = try? client.listSpeechModels()
        let images = await imagesTask
        let videos = await videosTask
        let music = await musicTask
        let speech = await speechTask

        var kinds: Set<MediaKind> = []
        if let images, !images.isEmpty { kinds.insert(.image) }
        if let videos, !videos.isEmpty { kinds.insert(.video) }
        if let music, !music.isEmpty { kinds.insert(.music) }
        if let speech, !speech.isEmpty { kinds.insert(.speech) }
        availableMediaKinds = kinds
    }
}
