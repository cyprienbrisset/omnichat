import SwiftUI
import OmniRouteKit

/// A real browser for OmniRoute's embedded MCP server — status heartbeat,
/// scoped tools, and audit stats, all read via the management API. Same
/// honesty rule as `MemoryView`: a missing management scope says so plainly
/// instead of showing empty sections that look like "nothing running."
struct MCPView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var status: MCPRawSnapshot?
    @State private var tools: [MCPTool] = []
    @State private var auditStats: MCPRawSnapshot?
    @State private var loadState: LoadState = .idle

    private enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case unavailable
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            content
        }
        .background(OmniTheme.paper)
        .background { OmniPaperTexture() }
        .navigationTitle("MCP")
        .task { await refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            OmniTheme.label("Passerelle", size: 10, color: OmniTheme.inkSoft)
            Text("Serveur MCP")
                .font(OmniTheme.serif(24, weight: .semibold))
                .foregroundStyle(OmniTheme.ink)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OmniTheme.paper)
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .idle, .loading:
            centeredMessage("Chargement…")
        case .unavailable:
            centeredMessage("Cette clé n'a pas les droits de gestion nécessaires pour lire l'état du serveur MCP. Teste-la depuis les Réglages.")
        case .failed(let message):
            centeredMessage(message)
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let status {
                        section(title: "État", snapshot: status)
                    }
                    toolsSection
                    if let auditStats {
                        section(title: "Statistiques d'audit", snapshot: auditStats)
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
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(_ title: String) -> some View {
        OmniTheme.label(title, size: 10, color: OmniTheme.accent)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }

    private func section(title: String, snapshot: MCPRawSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(title)
            if snapshot.sortedEntries.isEmpty {
                Text("Réponse vide.")
                    .font(OmniTheme.serif(13).italic())
                    .foregroundStyle(OmniTheme.inkSoft)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            } else {
                ForEach(snapshot.sortedEntries, id: \.key) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        Text(entry.key)
                            .font(OmniTheme.mono(10, weight: .semibold))
                            .foregroundStyle(OmniTheme.inkSoft)
                            .frame(width: 140, alignment: .leading)
                        Text(entry.value)
                            .font(OmniTheme.mono(11))
                            .foregroundStyle(OmniTheme.ink)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Outils (\(tools.count))")
            if tools.isEmpty {
                Text("Aucun outil exposé.")
                    .font(OmniTheme.serif(13).italic())
                    .foregroundStyle(OmniTheme.inkSoft)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            } else {
                ForEach(tools) { tool in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(tool.name)
                                .font(OmniTheme.mono(12, weight: .semibold))
                                .foregroundStyle(OmniTheme.ink)
                            if let phase = tool.phase {
                                OmniTheme.label(phase, size: 8, color: OmniTheme.accent)
                            }
                            if let auditLevel = tool.auditLevel {
                                Text(auditLevel)
                                    .font(OmniTheme.mono(9))
                                    .foregroundStyle(OmniTheme.inkSoft)
                            }
                        }
                        if let description = tool.description {
                            Text(description)
                                .font(OmniTheme.serif(13))
                                .foregroundStyle(OmniTheme.ink)
                        }
                        if let scopes = tool.scopes, !scopes.isEmpty {
                            Text("portées : \(scopes.joined(separator: ", "))")
                                .font(OmniTheme.mono(9))
                                .foregroundStyle(OmniTheme.inkSoft)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    Rectangle().fill(OmniTheme.hairline).frame(height: 1)
                }
            }
        }
    }

    private func refresh() async {
        guard appEnvironment.managementAccessState == .available else {
            loadState = appEnvironment.managementAccessState == .unavailable ? .unavailable : .idle
            return
        }
        loadState = .loading
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        do {
            async let statusResult = client.fetchMCPStatus()
            async let toolsResult = client.listMCPTools()
            async let auditResult = client.fetchMCPAuditStats()
            status = try await statusResult
            tools = try await toolsResult
            auditStats = try await auditResult
            loadState = .loaded
        } catch let error as OmniRouteError {
            loadState = .failed(error.userMessage)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
