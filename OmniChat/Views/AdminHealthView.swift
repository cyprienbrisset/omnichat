import SwiftUI
import OmniRouteKit

/// Serveur & santé (mockup 4b) — reuses `AppEnvironment.monitoringHealth`,
/// already fetched at launch (`/api/monitoring/health`), rather than firing
/// a redundant request the moment this page opens.
struct AdminHealthView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var isRefreshing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    OmniTheme.label("Passerelle", size: 10, color: OmniTheme.inkSoft)
                    Text("Serveur & santé")
                        .font(OmniTheme.serif(24, weight: .semibold))
                        .foregroundStyle(OmniTheme.ink)
                }
                Spacer()
                Button(isRefreshing ? "…" : "Actualiser") {
                    Task {
                        isRefreshing = true
                        await appEnvironment.refreshMonitoringHealth()
                        isRefreshing = false
                    }
                }
                .buttonStyle(.omniLink)
                .disabled(isRefreshing)
            }

            if let health = appEnvironment.monitoringHealth {
                statsGrid(health)
                if health.activeCount < health.catalogCount {
                    Text("\(health.activeCount) fournisseur(s) actif(s) sur \(health.catalogCount) au catalogue — l'écart n'est pas un bug d'OmniChat : la plupart des fournisseurs listés n'ont simplement aucune clé configurée côté OmniRoute (voir « Fournisseurs & clés »).")
                        .font(OmniTheme.serif(12).italic())
                        .foregroundStyle(OmniTheme.warning)
                        .frame(maxWidth: 480, alignment: .leading)
                }
            } else {
                Text("Pas encore chargé, ou la clé active n'a pas les droits de gestion — clique Actualiser.")
                    .font(OmniTheme.serif(13).italic())
                    .foregroundStyle(OmniTheme.inkSoft)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func statsGrid(_ health: MonitoringHealth) -> some View {
        HStack(spacing: 36) {
            stat("Catalogue", health.catalogCount)
            stat("Configurés", health.configuredCount)
            stat("Actifs", health.activeCount)
            stat("Surveillés", health.monitoredCount)
        }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(OmniTheme.serif(30, weight: .semibold))
                .foregroundStyle(OmniTheme.ink)
            OmniTheme.label(label, size: 8, color: OmniTheme.inkSoft)
        }
    }
}
