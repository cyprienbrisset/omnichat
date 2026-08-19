import SwiftUI
import SwiftData
import AppKit
import OmniRouteKit

/// A quick, real bulletin instead of a decorative popover — deliberately
/// built only from data this app can actually confirm, per an explicit
/// scoping decision: no fabricated "quota"/"success rate"/"P50" fields
/// against undocumented endpoints this environment has no real management
/// key to verify. So it shows real provider-health counts (already fetched
/// at launch) and a real "last routed reply" pulled from telemetry this
/// app already captured on its own messages — not a guess at what
/// OmniRoute's own analytics endpoints return.
struct MenuBarChatView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var lastRoutedMessage: Message?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            connectionRow

            if let health = appEnvironment.monitoringHealth {
                healthSection(health)
            }

            lastActivitySection

            Rectangle().fill(OmniTheme.hairline).frame(height: 1)

            Button("Ouvrir OmniChat") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .buttonStyle(.omniPrimary)
            .frame(maxWidth: .infinity)

            SettingsLink {
                Text("Réglages…")
            }
            .buttonStyle(.omniLink)
        }
        .padding(16)
        .frame(width: 260)
        .background(OmniTheme.paper)
        .task { loadLastRoutedMessage() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("O")
                .font(OmniTheme.serif(12, weight: .semibold))
                .foregroundStyle(OmniTheme.railText)
                .frame(width: 20, height: 20)
                .background(OmniTheme.rail)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                OmniTheme.label("Bulletin", size: 9, color: OmniTheme.inkSoft)
                Text("OmniChat")
                    .font(OmniTheme.serif(14, weight: .semibold))
                    .foregroundStyle(OmniTheme.ink)
            }
            Spacer()
            Text(Date().formatted(date: .omitted, time: .shortened))
                .font(OmniTheme.mono(10))
                .foregroundStyle(OmniTheme.inkSoft)
        }
    }

    private var connectionRow: some View {
        HStack(spacing: 5) {
            Circle().fill(OmniTheme.success).frame(width: 5, height: 5)
            Text(appEnvironment.activeProfile.baseURL.host ?? appEnvironment.activeProfile.baseURL.absoluteString)
                .font(OmniTheme.mono(10))
                .foregroundStyle(OmniTheme.inkSoft)
                .lineLimit(1)
        }
    }

    private func healthSection(_ health: MonitoringHealth) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            OmniTheme.label("Fournisseurs actifs", size: 9, color: OmniTheme.inkSoft)
            HStack {
                Text("\(health.activeCount) / \(health.catalogCount)")
                    .font(OmniTheme.serif(18, weight: .semibold))
                    .foregroundStyle(OmniTheme.ink)
                Spacer()
                if health.catalogCount > 0 {
                    Text("\(Int((Double(health.activeCount) / Double(health.catalogCount)) * 100))%")
                        .font(OmniTheme.mono(11))
                        .foregroundStyle(OmniTheme.inkSoft)
                }
            }
            if health.catalogCount > 0 {
                ProgressView(value: Double(health.activeCount), total: Double(health.catalogCount))
                    .tint(OmniTheme.success)
            }
        }
    }

    @ViewBuilder
    private var lastActivitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            OmniTheme.label("Dernière réponse routée", size: 9, color: OmniTheme.inkSoft)
            if let message = lastRoutedMessage {
                Text(routingSummary(for: message))
                    .font(OmniTheme.serif(12))
                    .foregroundStyle(OmniTheme.ink)
                Text(relativeTime(message.createdAt))
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.inkSoft)
            } else {
                Text("Aucune réponse avec télémétrie de routage pour l'instant.")
                    .font(OmniTheme.serif(11).italic())
                    .foregroundStyle(OmniTheme.inkSoft)
            }
        }
    }

    private func routingSummary(for message: Message) -> String {
        var parts: [String] = []
        switch (message.routingStrategy, message.routingProvider) {
        case let (strategy?, provider?) where strategy != "single":
            parts.append("\(strategy) → \(provider)")
        case (_, let provider?):
            parts.append(provider)
        case (let strategy?, nil):
            parts.append(strategy)
        default:
            break
        }
        if let latency = message.routingLatencyMs {
            parts.append("\(Int(latency)) ms")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// A small, bounded scan (most recent 20 messages, not the whole
    /// history) for the latest one that actually carries routing telemetry
    /// — real data this app captured itself from `X-OmniRoute-*` response
    /// headers, never a guess at a server-side analytics endpoint.
    private func loadLastRoutedMessage() {
        var descriptor = FetchDescriptor<Message>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 20
        guard let recent = try? context.fetch(descriptor) else { return }
        lastRoutedMessage = recent.first { $0.routingProvider != nil || $0.routingStrategy != nil }
    }
}
