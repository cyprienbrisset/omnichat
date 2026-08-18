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
        VStack(alignment: .leading, spacing: 18) {
            OmniTheme.eyebrow("Apparence")

            Picker("Thème", selection: Bindable(appEnvironment).themePreference) {
                ForEach(ThemePreference.allCases) { preference in
                    Text(preference.label).tag(preference)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Divider()

            OmniTheme.eyebrow("Connexion OmniRoute")

            VStack(alignment: .leading, spacing: 4) {
                Text("URL de base")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OmniTheme.secondaryText)
                TextField("http://localhost:20128/v1", text: $baseURLText)
                    .font(OmniTheme.mono(12))
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Clé API")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(OmniTheme.secondaryText)
                SecureField("Laisser vide pour ne pas la modifier", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            Button("Enregistrer", action: save)
                .buttonStyle(.omniPrimary)
        }
        .padding(20)
        .frame(width: 380)
        .background(OmniTheme.canvasBackground)
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
