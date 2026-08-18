import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        VStack(spacing: 22) {
            ConnectionSetupView(context: .settings)

            Rectangle().fill(OmniTheme.hairline).frame(height: 1)

            managementAccessRow

            if appEnvironment.managementAccessState == .available {
                Rectangle().fill(OmniTheme.hairline).frame(height: 1)
                providerHealthSection
            }

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
        .frame(width: 620)
        .background(OmniTheme.paper)
        .background { OmniPaperTexture() }
    }

    /// Real counts from `/api/monitoring/health` — the direct answer to
    /// "is my OmniRoute well configured?": most catalog entries can belong
    /// to providers with no credentials set up at all, and picking one of
    /// those anywhere in the app (chat, comparison, media generation)
    /// fails with a real server error, not an OmniChat bug.
    @ViewBuilder
    private var providerHealthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            OmniTheme.label("Fournisseurs", size: 9, color: OmniTheme.inkSoft)
            if let health = appEnvironment.monitoringHealth {
                Text("\(health.activeCount) actifs sur \(health.catalogCount) au catalogue (\(health.configuredCount) configurés).")
                    .font(OmniTheme.serif(14))
                    .foregroundStyle(OmniTheme.ink)
                if health.activeCount < health.catalogCount {
                    Text("La plupart des modèles du catalogue appartiennent à des fournisseurs sans identifiants configurés sur ce serveur OmniRoute — les sélectionner (chat, comparaison, génération média) échoue avec une vraie erreur serveur, pas un bug d'OmniChat. Configure-les depuis le tableau de bord OmniRoute (Fournisseurs) pour les rendre utilisables.")
                        .font(OmniTheme.serif(12).italic())
                        .foregroundStyle(OmniTheme.inkSoft)
                }
            } else {
                Text("Indisponible pour l'instant.")
                    .font(OmniTheme.serif(12).italic())
                    .foregroundStyle(OmniTheme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
