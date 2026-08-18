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
        }
        .modelContainer(modelContainer)

        MenuBarExtra("OmniChat", systemImage: "bubble.left.and.bubble.right") {
            MenuBarChatView()
                .environment(appEnvironment)
        }
        .modelContainer(modelContainer)

        Settings {
            SettingsView()
                .environment(appEnvironment)
        }
        .modelContainer(modelContainer)
    }
}
