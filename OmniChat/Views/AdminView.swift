import SwiftUI
import OmniRouteKit

/// Real configuration of the connected OmniRoute instance itself, via the
/// management API — not just reading OmniRoute's data (like Memory/MCP),
/// but changing it. Gated on management scope like the rest of this app's
/// `/api/*` features. Eight pages, grouped as Passerelle (server-facing:
/// health, providers, routing, compression) and Contrôle (policy-facing:
/// guardrails, agents, network, analytics) — two of the eight (Routage &
/// combos, Compression) stay honest placeholders: their real request/
/// response shapes aren't documented anywhere and need live discovery
/// against a real management key this environment doesn't have, the same
/// blocker recorded against task #39.
struct AdminView: View {
    @State private var page: AdminPage = .providers

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(OmniTheme.hairline).frame(width: 1)
            Group {
                switch page {
                case .health: AdminHealthView()
                case .providers: AdminProvidersView()
                case .routing:
                    AdminPlaceholderView(
                        title: "Routage & combos",
                        reason: "La forme réelle de /api/combos* n'est documentée qu'en prose — construire cet écran sur une hypothèse de champs serait risquer d'afficher une donnée réelle sous une mauvaise étiquette. Nécessite une découverte live contre une vraie clé de gestion."
                    )
                case .compression:
                    AdminPlaceholderView(
                        title: "Compression",
                        reason: "Même blocage que Routage & combos : /api/compression/preview et /api/settings/compression n'ont de schéma documenté qu'en prose, pas de noms de champs garantis."
                    )
                case .guardrails: AdminPoliciesView()
                case .agents: AdminAgentsView()
                case .network: AdminNetworkView()
                case .analytics: AdminAnalyticsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(OmniTheme.paper)
        .background { OmniPaperTexture() }
        .navigationTitle("Administration")
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                OmniTheme.label("Administration", size: 10, color: OmniTheme.inkSoft)
                Text("Huit pages")
                    .font(OmniTheme.serif(20, weight: .semibold))
                    .foregroundStyle(OmniTheme.ink)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            ScrollView {
                sidebarGroup(title: "Passerelle", pages: [.health, .providers, .routing, .compression])
                sidebarGroup(title: "Contrôle", pages: [.guardrails, .agents, .network, .analytics])
            }
            Spacer(minLength: 0)
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background(OmniTheme.paper)
    }

    private func sidebarGroup(title: String, pages: [AdminPage]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            OmniTheme.label(title, size: 9, color: OmniTheme.inkSoft)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 6)
            ForEach(pages) { candidate in
                sidebarRow(candidate)
            }
        }
    }

    private func sidebarRow(_ candidate: AdminPage) -> some View {
        let isSelected = page == candidate
        return Button {
            page = candidate
        } label: {
            HStack {
                Text(candidate.label)
                    .font(OmniTheme.serif(13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? OmniTheme.ink : OmniTheme.inkSoft)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? OmniTheme.paperMuted : Color.clear)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle().fill(OmniTheme.accent).frame(width: 2)
            }
        }
    }
}

enum AdminPage: String, CaseIterable, Identifiable {
    case health, providers, routing, compression, guardrails, agents, network, analytics
    var id: String { rawValue }
    var label: String {
        switch self {
        case .health: "Serveur & santé"
        case .providers: "Fournisseurs & clés"
        case .routing: "Routage & combos"
        case .compression: "Compression"
        case .guardrails: "Garde-fous"
        case .agents: "Agents & outils"
        case .network: "Réseau & confidentialité"
        case .analytics: "Analytique & coûts"
        }
    }
}

// MARK: - Shared raw-field rendering (undocumented shapes)

/// Every raw key/value pair a management-API resource returned, sorted for
/// stable display — the honest fallback whenever a shape isn't documented.
struct RawFieldRows: View {
    let entries: [(key: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(entries, id: \.key) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Text(entry.key)
                        .font(OmniTheme.mono(9, weight: .semibold))
                        .foregroundStyle(OmniTheme.inkSoft)
                        .frame(width: 130, alignment: .leading)
                    Text(entry.value)
                        .font(OmniTheme.mono(10))
                        .foregroundStyle(OmniTheme.ink)
                }
            }
        }
    }
}

/// A small pill used to surface one real fact at a glance — status, auth
/// type, plan, whatever the raw snapshot actually contains. Never invented:
/// every call site only builds one when the underlying field was present.
struct AdminBadge: View {
    let text: String
    var color: Color = OmniTheme.accent

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

/// A page that's real (it's in the mockup's eight) but not yet backed by
/// verified data — shown honestly instead of built on a guessed schema.
struct AdminPlaceholderView: View {
    let title: String
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OmniTheme.label("Bientôt", size: 9, color: OmniTheme.inkSoft)
            Text(title)
                .font(OmniTheme.serif(24, weight: .semibold))
                .foregroundStyle(OmniTheme.ink)
            Text(reason)
                .font(OmniTheme.serif(13).italic())
                .foregroundStyle(OmniTheme.inkSoft)
                .frame(maxWidth: 480, alignment: .leading)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
