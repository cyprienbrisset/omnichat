import SwiftUI
import SwiftData
import OmniRouteKit

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var context
    @State private var baseURLText = ""
    @State private var apiKey = ""
    @State private var saveError: String?

    var body: some View {
        Form {
            TextField("URL OmniRoute", text: $baseURLText)
            SecureField("Clé API (laisser vide pour ne pas la modifier)", text: $apiKey)
            if let saveError {
                Text(saveError).foregroundStyle(.red)
            }
            Button("Enregistrer", action: save)
        }
        .padding()
        .frame(width: 360)
        .onAppear {
            baseURLText = appEnvironment.activeProfile.baseURL.absoluteString
        }
    }

    private func save() {
        guard let url = URL(string: baseURLText),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            saveError = "URL invalide"
            return
        }
        do {
            try appEnvironment.persistActiveProfile(baseURL: url, apiKey: apiKey, context: context)
            saveError = nil
        } catch {
            saveError = "Impossible d'enregistrer la clé: \(error.localizedDescription)"
        }
    }
}
