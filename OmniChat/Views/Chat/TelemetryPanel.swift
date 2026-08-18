import SwiftUI

/// Conversation-level metrics in the margin, mirroring the mockup's layout
/// but populated only from telemetry this app actually captures — no quota
/// or combo-comparison data yet, since those need work not done here.
struct TelemetryPanel: View {
    let totals: ConversationTelemetryTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            OmniTheme.label("Métriques", size: 10, color: OmniTheme.inkSoft)

            metric(label: "Jetons", value: "\(totals.totalTokensIn)→\(totals.totalTokensOut)")

            if totals.totalCostUSD > 0 {
                metric(label: "Coût", value: String(format: "$%.4f", totals.totalCostUSD))
            }

            if totals.cacheEligibleTurns > 0 {
                metric(label: "Cache sémantique", value: "\(totals.cacheHits) coup(s) sur \(totals.cacheEligibleTurns) tour(s)")
            }

            Spacer()
        }
        .padding(18)
        .frame(width: 190, alignment: .leading)
        .background(OmniTheme.paperMuted)
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            OmniTheme.label(label, size: 8, color: OmniTheme.inkSoft)
            Text(value)
                .font(OmniTheme.serif(15, weight: .semibold))
                .foregroundStyle(OmniTheme.ink)
        }
    }
}
