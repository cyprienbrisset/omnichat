import SwiftUI
import OmniRouteKit

/// Garde-fous (mockup 4b) — `GET /api/policies` ("Manage routing
/// policies"). Response shape isn't documented beyond that one line, so
/// each policy stays a raw, honest snapshot — same treatment as Providers.
struct AdminPoliciesView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var policies: [AdminRawSnapshot] = []
    @State private var loadState: LoadState = .loading

    private enum LoadState: Equatable { case loading, loaded, failed(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            content
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            OmniTheme.label("Contrôle", size: 10, color: OmniTheme.inkSoft)
            Text("Garde-fous")
                .font(OmniTheme.serif(24, weight: .semibold))
                .foregroundStyle(OmniTheme.ink)
            Text("Politiques de routage définies sur le serveur — GET /api/policies. Forme exacte non documentée, affichée telle quelle.")
                .font(OmniTheme.serif(12).italic())
                .foregroundStyle(OmniTheme.inkSoft)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            centeredMessage("Chargement…")
        case .failed(let message):
            centeredMessage(message)
        case .loaded:
            if policies.isEmpty {
                centeredMessage("Aucune politique définie sur ce serveur.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(policies) { policy in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(policy.id)
                                    .font(OmniTheme.mono(10, weight: .semibold))
                                    .foregroundStyle(OmniTheme.ink)
                                RawFieldRows(entries: policy.sortedEntries)
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func centeredMessage(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(OmniTheme.serif(13).italic())
                .foregroundStyle(OmniTheme.inkSoft)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        loadState = .loading
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            policies = try await client.listPolicies()
            loadState = .loaded
        } catch let error as OmniRouteError {
            loadState = .failed(error.userMessage)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
