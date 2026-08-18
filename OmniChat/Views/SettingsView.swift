import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        VStack(spacing: 22) {
            ConnectionSetupView(context: .settings)

            Rectangle().fill(OmniTheme.hairline).frame(height: 1)

            managementAccessRow

            Rectangle().fill(OmniTheme.hairline).frame(height: 1)

            VStack(alignment: .leading, spacing: 10) {
                OmniTheme.label("Apparence", size: 9, color: OmniTheme.inkSoft)
                Picker("Thème", selection: Bindable(appEnvironment).themePreference) {
                    ForEach(ThemePreference.allCases) { preference in
                        Text(preference.label).tag(preference)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(36)
        .frame(width: 460)
        .background(OmniTheme.paper)
        .background { OmniPaperTexture() }
    }

    @ViewBuilder
    private var managementAccessRow: some View {
        HStack(spacing: 5) {
            switch appEnvironment.managementAccessState {
            case .unknown:
                Text("Droits de gestion : teste la connexion pour vérifier")
                    .font(OmniTheme.mono(10))
                    .foregroundStyle(OmniTheme.inkSoft)
            case .checking:
                Text("Vérification des droits de gestion…")
                    .font(OmniTheme.mono(10))
                    .foregroundStyle(OmniTheme.inkSoft)
            case .available:
                Circle().fill(OmniTheme.success).frame(width: 5, height: 5)
                Text("Droits de gestion disponibles sur cette clé")
                    .font(OmniTheme.mono(10, weight: .semibold))
                    .foregroundStyle(OmniTheme.success)
            case .unavailable:
                Circle().fill(OmniTheme.inkSoft).frame(width: 5, height: 5)
                Text("Droits de gestion non disponibles sur cette clé")
                    .font(OmniTheme.mono(10))
                    .foregroundStyle(OmniTheme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
