import SwiftUI
import OmniRouteKit

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var baseURLText = EndpointProfile.defaultLocal.baseURL.absoluteString
    @State private var apiKey = ""
    @State private var saveError: String?

    var body: some View {
        Form {
            TextField("URL OmniRoute", text: $baseURLText)
            SecureField("Clé API", text: $apiKey)
            if let saveError {
                Text(saveError).foregroundStyle(.red)
            }
            Button("Enregistrer", action: save)
        }
        .padding()
        .frame(width: 360)
    }

    private func save() {
        guard let url = URL(string: baseURLText) else {
            saveError = "URL invalide"
            return
        }
        let profile = EndpointProfile(name: "Défaut", baseURL: url)
        appEnvironment.activeProfile = profile
        do {
            try appEnvironment.credentialStore.setAPIKey(apiKey, for: profile.id)
            saveError = nil
        } catch {
            saveError = "Impossible d'enregistrer la clé: \(error.localizedDescription)"
        }
    }
}
