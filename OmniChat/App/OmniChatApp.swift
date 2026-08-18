import SwiftUI
import SwiftData

@main
struct OmniChatApp: App {
    let modelContainer: ModelContainer
    @State private var appEnvironment = AppEnvironment()

    init() {
        do {
            modelContainer = try ModelContainer(for: Conversation.self, Message.self, StoredEndpointProfile.self)
        } catch {
            fatalError("Impossible d'initialiser SwiftData: \(error)")
        }
        appEnvironment.loadPersistedProfile(from: ModelContext(modelContainer))

        let diagnosticLogger = appEnvironment.diagnosticLogger
        Task { try? await diagnosticLogger.purgeExpired() }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(appEnvironment)
                .preferredColorScheme(appEnvironment.themePreference.colorScheme)
        }
        .modelContainer(modelContainer)

        MenuBarExtra("OmniChat", systemImage: "diamond.fill") {
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
