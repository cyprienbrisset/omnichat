import SwiftUI
import OmniRouteKit

/// Agents & outils (mockup 4b) — `GET /api/acp/agents`, the one new page
/// this pass backs with a fully documented response shape (the API
/// reference includes a real JSON example), so every field here is typed,
/// never a raw snapshot.
struct AdminAgentsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var agents: [ACPAgent] = []
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
            Text("Agents & outils")
                .font(OmniTheme.serif(24, weight: .semibold))
                .foregroundStyle(OmniTheme.ink)
            Text("Agents CLI détectés par OmniRoute, intégrés ou personnalisés — GET /api/acp/agents.")
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
            if agents.isEmpty {
                centeredMessage("Aucun agent détecté.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(agents) { agent in
                            agentRow(agent)
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

    private func agentRow(_ agent: ACPAgent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(agent.installed ? OmniTheme.success : OmniTheme.inkSoft)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(agent.name)
                        .font(OmniTheme.serif(14, weight: .semibold))
                        .foregroundStyle(OmniTheme.ink)
                    if agent.isCustom {
                        AdminBadge(text: "custom", color: OmniTheme.accent)
                    }
                    if let protocolName = agent.protocolName {
                        AdminBadge(text: protocolName, color: OmniTheme.inkSoft)
                    }
                }
                HStack(spacing: 10) {
                    if let binary = agent.binary {
                        Text(binary).font(OmniTheme.mono(9)).foregroundStyle(OmniTheme.inkSoft)
                    }
                    if let version = agent.version {
                        Text("v\(version)").font(OmniTheme.mono(9)).foregroundStyle(OmniTheme.inkSoft)
                    }
                    if let providerAlias = agent.providerAlias {
                        Text("→ \(providerAlias)").font(OmniTheme.mono(9)).foregroundStyle(OmniTheme.inkSoft)
                    }
                }
            }
            Spacer()
            Text(agent.installed ? "Installé" : "Introuvable")
                .font(OmniTheme.mono(9))
                .foregroundStyle(agent.installed ? OmniTheme.success : OmniTheme.danger)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private func load() async {
        loadState = .loading
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            let response = try await client.listACPAgents()
            agents = response.agents
            loadState = .loaded
        } catch let error as OmniRouteError {
            loadState = .failed(error.userMessage)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
