import SwiftUI
import SwiftData
import OmniRouteKit

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var context
    @State private var baseURLText = ""
    @State private var apiKey = ""
    @State private var saveError: String?
    @State private var connectionTest: ConnectionTestState = .idle

    private enum ConnectionTestState: Equatable {
        case idle
        case testing
        case success(modelCount: Int)
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 10) {
                Text("O")
                    .font(OmniTheme.serif(18, weight: .semibold))
                    .foregroundStyle(OmniTheme.railText)
                    .frame(width: 40, height: 40)
                    .background(OmniTheme.rail)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                OmniTheme.label("OmniChat pour macOS")

                Text("Connexion à OmniRoute")
                    .font(OmniTheme.serif(22, weight: .semibold))
                    .foregroundStyle(OmniTheme.ink)

                Text("Renseigne l'endpoint et la clé API de ta passerelle OmniRoute.")
                    .font(OmniTheme.serif(12).italic())
                    .foregroundStyle(OmniTheme.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            Rectangle().fill(OmniTheme.hairline).frame(height: 1)

            OmniTheme.label("Connexion OmniRoute", size: 10, color: OmniTheme.inkSoft)

            labeledField(label: "URL de base") {
                TextField("http://localhost:20128/v1", text: $baseURLText)
                    .font(OmniTheme.mono(12))
                    .textFieldStyle(.plain)
            }

            labeledField(label: "Clé API") {
                SecureField("Laisser vide pour ne pas la modifier", text: $apiKey)
                    .font(OmniTheme.mono(12))
                    .textFieldStyle(.plain)
            }

            connectionTestRow

            if let saveError {
                Text(saveError)
                    .font(OmniTheme.mono(11))
                    .foregroundStyle(OmniTheme.danger)
            }

            Button("Enregistrer", action: save)
                .buttonStyle(.omniPrimary)
                .frame(maxWidth: .infinity)

            Rectangle().fill(OmniTheme.hairline).frame(height: 1)

            OmniTheme.label("Apparence", size: 10, color: OmniTheme.inkSoft)

            Picker("Thème", selection: Bindable(appEnvironment).themePreference) {
                ForEach(ThemePreference.allCases) { preference in
                    Text(preference.label).tag(preference)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(24)
        .frame(width: 420)
        .background(OmniTheme.paper)
        .onAppear {
            baseURLText = appEnvironment.activeProfile.baseURL.absoluteString
        }
    }

    @ViewBuilder
    private func labeledField<Field: View>(label: String, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            OmniTheme.label(label, size: 9, color: OmniTheme.inkSoft)
            field()
                .padding(.bottom, 6)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(OmniTheme.hairline).frame(height: 1)
                }
        }
    }

    @ViewBuilder
    private var connectionTestRow: some View {
        HStack(spacing: 10) {
            Button("Tester la connexion actuelle", action: testConnection)
                .buttonStyle(.omniLink)
                .disabled(connectionTest == .testing)

            Spacer()

            switch connectionTest {
            case .idle:
                EmptyView()
            case .testing:
                Text("Test en cours…")
                    .font(OmniTheme.mono(10))
                    .foregroundStyle(OmniTheme.inkSoft)
            case .success(let modelCount):
                HStack(spacing: 5) {
                    Circle().fill(OmniTheme.success).frame(width: 5, height: 5)
                    Text("Joignable · \(modelCount) modèles")
                        .font(OmniTheme.mono(10, weight: .semibold))
                        .foregroundStyle(OmniTheme.success)
                }
            case .failure(let message):
                HStack(spacing: 5) {
                    Circle().fill(OmniTheme.danger).frame(width: 5, height: 5)
                    Text(message)
                        .font(OmniTheme.mono(10, weight: .semibold))
                        .foregroundStyle(OmniTheme.danger)
                        .lineLimit(2)
                }
            }
        }
    }

    /// Exercises the already-configured, saved profile with a real
    /// `listModels()` call rather than faking a reachability indicator —
    /// tests the currently active (saved) connection, not unsaved form text.
    private func testConnection() {
        connectionTest = .testing
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        Task {
            do {
                let models = try await client.listModels()
                connectionTest = .success(modelCount: models.count)
            } catch let error as OmniRouteError {
                connectionTest = .failure(error.userMessage)
            } catch {
                connectionTest = .failure(error.localizedDescription)
            }
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
            connectionTest = .idle
        } catch {
            saveError = "Impossible d'enregistrer la clé: \(error.localizedDescription)"
        }
    }
}
