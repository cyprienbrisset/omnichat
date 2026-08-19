import SwiftUI
import OmniRouteKit

/// Réseau & confidentialité (mockup 4b) — two undocumented-shape resources
/// (`GET /api/settings/proxy`, `GET /api/settings/ip-filter`), each shown
/// as an honest raw snapshot rather than a guessed form.
struct AdminNetworkView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var proxySettings: AdminRawSnapshot?
    @State private var ipFilterSettings: AdminRawSnapshot?
    @State private var proxyError: String?
    @State private var ipFilterError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Rectangle().fill(OmniTheme.hairline).frame(height: 1)
                section(title: "Proxy réseau", subtitle: "GET /api/settings/proxy", snapshot: proxySettings, error: proxyError)
                Rectangle().fill(OmniTheme.hairline).frame(height: 1)
                section(title: "Filtrage IP", subtitle: "GET /api/settings/ip-filter", snapshot: ipFilterSettings, error: ipFilterError)
            }
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            OmniTheme.label("Contrôle", size: 10, color: OmniTheme.inkSoft)
            Text("Réseau & confidentialité")
                .font(OmniTheme.serif(24, weight: .semibold))
                .foregroundStyle(OmniTheme.ink)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(title: String, subtitle: String, snapshot: AdminRawSnapshot?, error: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            OmniTheme.label(title, size: 9, color: OmniTheme.inkSoft)
            Text(subtitle)
                .font(OmniTheme.mono(9))
                .foregroundStyle(OmniTheme.inkSoft)
            if let error {
                Text(error)
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.danger)
            } else if let snapshot {
                if snapshot.sortedEntries.isEmpty {
                    Text("Aucun champ retourné.")
                        .font(OmniTheme.serif(12).italic())
                        .foregroundStyle(OmniTheme.inkSoft)
                } else {
                    RawFieldRows(entries: snapshot.sortedEntries)
                }
            } else {
                Text("Chargement…")
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.inkSoft)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            proxySettings = try await client.fetchProxySettings()
        } catch let error as OmniRouteError {
            proxyError = error.userMessage
        } catch {
            proxyError = error.localizedDescription
        }
        do {
            ipFilterSettings = try await client.fetchIPFilterSettings()
        } catch let error as OmniRouteError {
            ipFilterError = error.userMessage
        } catch {
            ipFilterError = error.localizedDescription
        }
    }
}
