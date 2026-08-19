import SwiftUI
import SwiftData

@main
struct OmniChatApp: App {
    let modelContainer: ModelContainer
    @State private var appEnvironment = AppEnvironment()

    init() {
        do {
            modelContainer = try ModelContainer(
                for: Conversation.self, Message.self, StoredEndpointProfile.self, MediaItem.self, SearchPassage.self,
                FusionSession.self, FusionRound.self, FusionSourceResponse.self
            )
        } catch {
            fatalError("Impossible d'initialiser SwiftData: \(error)")
        }
        appEnvironment.loadPersistedProfile(from: ModelContext(modelContainer))

        let diagnosticLogger = appEnvironment.diagnosticLogger
        Task { try? await diagnosticLogger.purgeExpired() }

        let environment = appEnvironment
        Task {
            await environment.refreshManagementAccess()
            await environment.refreshMonitoringHealth()
        }
        Task { await environment.refreshCatalogSummary() }
        Task { await environment.refreshAvailableMediaKinds() }
        Task { await environment.refreshTranscriptionAvailability() }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(appEnvironment)
                .preferredColorScheme(appEnvironment.themePreference.colorScheme)
        }
        .modelContainer(modelContainer)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("OmniChat", systemImage: "doc.text.fill") {
            MenuBarChatView()
                .environment(appEnvironment)
                .preferredColorScheme(appEnvironment.themePreference.colorScheme)
        }
        .modelContainer(modelContainer)

        Settings {
            SettingsView()
                .environment(appEnvironment)
                .preferredColorScheme(appEnvironment.themePreference.colorScheme)
        }
        .modelContainer(modelContainer)
    }
}
