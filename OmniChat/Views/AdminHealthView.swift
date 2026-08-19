import SwiftUI
import OmniRouteKit

/// Serveur & santé (mockup 4b) — reuses `AppEnvironment.monitoringHealth`,
/// already fetched at launch (`/api/monitoring/health`), rather than firing
/// a redundant request the moment this page opens. Every field shown here
/// (version, uptime, credential/circuit-breaker health, provider breakers)
/// is confirmed real against a live OmniRoute 3.8.49 instance — see
/// `MonitoringHealth`'s doc comment. Two things the original mockup showed
/// (a 30-day availability % and an hourly latency chart) aren't backed by
/// any real endpoint: `/api/monitoring/{incidents,history,uptime,
/// availability,latency-history,status}` and `/api/incidents` all returned
/// a real `404 unknown_route` in direct testing, so those are left out
/// rather than invented — provider circuit-breaker state fills a similar
/// role honestly instead of a fabricated incident log.
struct AdminHealthView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var isRefreshing = false
    @State private var isShowingRawLog = false
    @State private var endpointProbe: EndpointProbeState = .idle

    private enum EndpointProbeState: Equatable {
        case idle, probing, success(statusCode: Int, latencyMs: Int), failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let health = appEnvironment.monitoringHealth {
                    subtitle(health)
                    endpointSection
                    statsGrid(health)
                    if health.activeCount < health.catalogCount {
                        Text("\(health.activeCount) fournisseur(s) actif(s) sur \(health.catalogCount) au catalogue — l'écart n'est pas un bug d'OmniChat : la plupart des fournisseurs listés n'ont simplement aucune clé configurée côté OmniRoute (voir « Fournisseurs & clés »).")
                            .font(OmniTheme.serif(12).italic())
                            .foregroundStyle(OmniTheme.warning)
                            .frame(maxWidth: 480, alignment: .leading)
                    }
                    if isShowingRawLog {
                        rawLog(health)
                    }
                    breakersSection(health)
                } else {
                    endpointSection
                    Text("Pas encore chargé, ou la clé active n'a pas les droits de gestion — clique Re-sonder.")
                        .font(OmniTheme.serif(13).italic())
                        .foregroundStyle(OmniTheme.inkSoft)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task { await probeEndpoint() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                OmniTheme.label("Passerelle", size: 10, color: OmniTheme.inkSoft)
                Text("Serveur & santé")
                    .font(OmniTheme.serif(24, weight: .semibold))
                    .foregroundStyle(OmniTheme.ink)
            }
            Spacer()
            Button(isShowingRawLog ? "Masquer" : "Journal brut") {
                isShowingRawLog.toggle()
            }
            .buttonStyle(.omniLink)
            Button(isRefreshing ? "…" : "Re-sonder") {
                Task {
                    isRefreshing = true
                    await appEnvironment.refreshMonitoringHealth()
                    await probeEndpoint()
                    isRefreshing = false
                }
            }
            .buttonStyle(.omniPrimary)
            .disabled(isRefreshing)
        }
    }

    private func subtitle(_ health: MonitoringHealth) -> some View {
        Text("OmniRoute v\(health.version) · en ligne depuis \(uptimeDescription(health.uptimeSeconds))")
            .font(OmniTheme.mono(11))
            .foregroundStyle(OmniTheme.inkSoft)
    }

    private func uptimeDescription(_ seconds: Double) -> String {
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        if days > 0 { return "\(days) j \(hours) h" }
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 { return "\(hours) h \(minutes) min" }
        return "\(minutes) min"
    }

    private var endpointSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            OmniTheme.label("Point de terminaison", size: 9, color: OmniTheme.inkSoft)
            HStack(spacing: 12) {
                Text(appEnvironment.activeProfile.baseURL.absoluteString)
                    .font(OmniTheme.mono(12))
                    .foregroundStyle(OmniTheme.ink)
                    .padding(10)
                    .background(OmniTheme.paperMuted)
                Spacer()
                endpointProbeBadge
            }
        }
    }

    @ViewBuilder
    private var endpointProbeBadge: some View {
        switch endpointProbe {
        case .idle:
            EmptyView()
        case .probing:
            Text("…").font(OmniTheme.mono(11)).foregroundStyle(OmniTheme.inkSoft)
        case .success(let statusCode, let latencyMs):
            HStack(spacing: 5) {
                Circle().fill((200..<300).contains(statusCode) ? OmniTheme.success : OmniTheme.danger).frame(width: 6, height: 6)
                Text("\(statusCode) · \(latencyMs) ms").font(OmniTheme.mono(11)).foregroundStyle(OmniTheme.inkSoft)
            }
        case .failed(let message):
            Text(message).font(OmniTheme.mono(10)).foregroundStyle(OmniTheme.danger)
        }
    }

    private func statsGrid(_ health: MonitoringHealth) -> some View {
        HStack(spacing: 36) {
            stat("Sains", health.credentialHealth.healthy, color: OmniTheme.success)
            stat("Sans clé", max(0, health.catalogCount - health.configuredCount), color: OmniTheme.warning)
            stat("En panne", health.credentialHealth.failed, color: health.credentialHealth.failed > 0 ? OmniTheme.danger : OmniTheme.ink)
            stat("Connexions actives", health.activeConnections, color: OmniTheme.ink)
        }
    }

    private func stat(_ label: String, _ value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(OmniTheme.serif(30, weight: .semibold))
                .foregroundStyle(color)
            OmniTheme.label(label, size: 8, color: OmniTheme.inkSoft)
        }
    }

    private func rawLog(_ health: MonitoringHealth) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            OmniTheme.label("Journal brut (champs réels décodés)", size: 9, color: OmniTheme.inkSoft)
            VStack(alignment: .leading, spacing: 2) {
                Text("status: \(health.status)")
                Text("version: \(health.version)")
                Text("uptime: \(Int(health.uptimeSeconds)) s")
                Text("activeConnections: \(health.activeConnections)")
                Text("credentialHealth: total=\(health.credentialHealth.total) healthy=\(health.credentialHealth.healthy) failed=\(health.credentialHealth.failed) stale=\(health.credentialHealth.stale) unknown=\(health.credentialHealth.unknown)")
                Text("circuitBreakers: open=\(health.circuitBreakers.open) halfOpen=\(health.circuitBreakers.halfOpen) degraded=\(health.circuitBreakers.degraded) closed=\(health.circuitBreakers.closed)")
                Text("providerSummary: catalog=\(health.catalogCount) configured=\(health.configuredCount) active=\(health.activeCount) monitored=\(health.monitoredCount)")
            }
            .font(OmniTheme.mono(10))
            .foregroundStyle(OmniTheme.inkSoft)
        }
        .padding(12)
        .background(OmniTheme.paperMuted)
    }

    @ViewBuilder
    private func breakersSection(_ health: MonitoringHealth) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            OmniTheme.label("Disjoncteurs par fournisseur", size: 9, color: OmniTheme.inkSoft)
            if health.providerBreakers.isEmpty {
                Text("Aucun disjoncteur actif — tous les fournisseurs surveillés répondent normalement.")
                    .font(OmniTheme.serif(12).italic())
                    .foregroundStyle(OmniTheme.inkSoft)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(health.providerBreakers) { breaker in
                        HStack(spacing: 12) {
                            Circle().fill(breakerColor(breaker.state)).frame(width: 6, height: 6)
                            Text(breaker.provider).font(OmniTheme.mono(11, weight: .semibold)).foregroundStyle(OmniTheme.ink)
                            Text(breaker.state).font(OmniTheme.mono(10)).foregroundStyle(breakerColor(breaker.state))
                            if breaker.failureCount > 0 {
                                Text("\(breaker.failureCount) échec(s)").font(OmniTheme.mono(10)).foregroundStyle(OmniTheme.inkSoft)
                            }
                            Spacer()
                            if let lastFailure = breaker.lastFailure, let relative = AdminHealthDateFormatting.relativeDescription(for: lastFailure) {
                                Text(relative).font(OmniTheme.mono(9)).foregroundStyle(OmniTheme.inkSoft)
                            }
                        }
                        .padding(.vertical, 8)
                        Rectangle().fill(OmniTheme.hairline).frame(height: 1)
                    }
                }
            }
        }
    }

    private func breakerColor(_ state: String) -> Color {
        switch state.uppercased() {
        case "OPEN": OmniTheme.danger
        case "HALF_OPEN", "HALFOPEN": OmniTheme.warning
        default: OmniTheme.success
        }
    }

    /// Times a real `GET /v1/models` — the endpoint every profile is
    /// guaranteed to have, so this works even without management access —
    /// rather than fabricating a status/latency pair.
    private func probeEndpoint() async {
        endpointProbe = .probing
        let client = OmniRouteClient(profile: appEnvironment.activeProfile, credentialStore: appEnvironment.credentialStore)
        let started = Date()
        do {
            _ = try await client.listModels()
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            endpointProbe = .success(statusCode: 200, latencyMs: elapsedMs)
        } catch let error as OmniRouteError {
            endpointProbe = .failed(error.userMessage)
        } catch {
            endpointProbe = .failed(error.localizedDescription)
        }
    }
}

private enum AdminHealthDateFormatting {
    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.unitsStyle = .short
        return formatter
    }()

    static func relativeDescription(for isoString: String) -> String? {
        guard let date = iso.date(from: isoString) else { return nil }
        return relative.localizedString(for: date, relativeTo: Date())
    }
}
