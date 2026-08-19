import SwiftUI
import SwiftData
import AppKit
import OmniRouteKit

/// A quick, real bulletin instead of a decorative popover — every section
/// is gated on real, confirmed data: provider-health counts (fetched at
/// launch), a global token quota once its apiKeyId is on file (see
/// `AppEnvironment.globalQuota`), a requests/success/P50 aggregate over
/// `/api/usage/model-latency-stats`'s real per-route entries (see
/// `BulletinHealthSummary`), the last model cooldown/failover if one is
/// active, and a real "last routed reply" pulled from telemetry this app
/// already captured on its own messages. Any section stays absent — never
/// fabricated — when its underlying data isn't available.
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

            if let globalQuota = appEnvironment.globalQuota {
                quotaSection(globalQuota)
            }

            if let summary = appEnvironment.bulletinHealthSummary {
                healthSummarySection(summary)
            }

            lastActivitySection

            if let cooldown = appEnvironment.lastModelCooldown {
                cooldownSection(cooldown)
            }

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
        .task {
            loadLastRoutedMessage()
            await appEnvironment.refreshGlobalQuota()
            await appEnvironment.refreshBulletinHealthSummary()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image("BrandMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(OmniTheme.railText)
                .padding(3)
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

    /// Real global token quota (`GET /api/usage/token-limits`, scope
    /// "global") for whichever apiKeyId the user has entered once in
    /// Administration › Analytique — see `AppEnvironment.globalQuota`'s
    /// doc comment. Absent entirely (not a fake bar) until that's set up.
    private func quotaSection(_ quota: TokenLimitEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            OmniTheme.label("Quota global", size: 9, color: OmniTheme.inkSoft)
            if let remaining = quota.remaining {
                HStack {
                    Text("\(remaining) restants")
                        .font(OmniTheme.serif(14, weight: .semibold))
                        .foregroundStyle(OmniTheme.ink)
                    Spacer()
                    Text("/ \(quota.tokenLimit) jetons")
                        .font(OmniTheme.mono(10))
                        .foregroundStyle(OmniTheme.inkSoft)
                }
                if quota.tokenLimit > 0 {
                    let fraction = max(0, min(1, Double(remaining) / Double(quota.tokenLimit)))
                    ProgressView(value: fraction)
                        .tint(fraction < 0.15 ? OmniTheme.danger : (fraction < 0.4 ? OmniTheme.warning : OmniTheme.success))
                }
            } else {
                Text("\(quota.tokensUsed ?? 0) / \(quota.tokenLimit) jetons utilisés")
                    .font(OmniTheme.serif(13, weight: .semibold))
                    .foregroundStyle(OmniTheme.ink)
            }
        }
    }

    /// Real requests/success/P50 aggregate — see
    /// `AppEnvironment.BulletinHealthSummary`'s doc comment for exactly how
    /// this is computed from `GET /api/usage/model-latency-stats`'s real
    /// per-route entries (P50 here is a request-weighted mean of each
    /// route's own p50, not a server-reported global percentile).
    private func healthSummarySection(_ summary: BulletinHealthSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            OmniTheme.label("Requêtes (\(summary.windowHours) h)", size: 9, color: OmniTheme.inkSoft)
            HStack(spacing: 16) {
                statColumn(String(summary.totalRequests), label: "requêtes")
                statColumn(
                    "\(Int(summary.successRate * 100))%",
                    label: "succès",
                    color: summary.successRate >= 0.8 ? OmniTheme.success : (summary.successRate >= 0.4 ? OmniTheme.warning : OmniTheme.danger)
                )
                statColumn("\(Int(summary.weightedP50Ms)) ms", label: "P50")
            }
        }
    }

    private func statColumn(_ value: String, label: String, color: Color = OmniTheme.ink) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(OmniTheme.serif(15, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(OmniTheme.mono(8))
                .foregroundStyle(OmniTheme.inkSoft)
        }
    }

    /// Real but shape-unconfirmed — see `AppEnvironment.lastModelCooldown`'s
    /// doc comment. Shown as raw fields rather than guessed labels.
    private func cooldownSection(_ cooldown: AdminRawSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            OmniTheme.label("Dernière bascule", size: 9, color: OmniTheme.inkSoft)
            RawFieldRows(entries: cooldown.sortedEntries)
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
