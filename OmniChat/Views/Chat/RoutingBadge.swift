import SwiftUI

/// A compact, real-data-only echo of the routing decision behind the most
/// recent response — omits anything this session doesn't actually capture
/// (combo target count, compression ratio) rather than inventing it.
struct RoutingBadge: View {
    let totals: ConversationTelemetryTotals
    let fallbackLabel: String

    var body: some View {
        HStack(spacing: 6) {
            if let strategy = totals.lastRoutingStrategy, let provider = totals.lastRoutingProvider {
                Text("\(strategy) → \(provider)")
            } else {
                Text(fallbackLabel)
            }
            if let latency = totals.lastRoutingLatencyMs {
                Text("· \(Int(latency)) ms")
            }
        }
        .font(OmniTheme.mono(10, weight: .semibold))
        .foregroundStyle(OmniTheme.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(OmniTheme.accent.opacity(0.4), lineWidth: 1)
        )
    }
}
