import SwiftUI
import OmniRouteKit

/// One card per error code, echoing the mockup's per-status treatment
/// rather than a single generic banner — the code and color anchor what
/// went wrong, the retry action reads correctly for what actually resumes.
struct ErrorBannerView: View {
    let error: OmniRouteError
    let retryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(error.codeLabel)
                    .font(OmniTheme.serif(20, weight: .bold))
                    .foregroundStyle(error.codeColor)
                OmniTheme.label(error.codeTitle, size: 10, color: OmniTheme.inkSoft)
            }

            Text(error.userMessage)
                .font(OmniTheme.serif(13))
                .foregroundStyle(OmniTheme.ink)

            if case .rateLimited(let retryAfter?) = error {
                RateLimitCountdown(totalSeconds: retryAfter)
            }

            // Retrying with the same rejected key just fails again — the
            // mockup's 401 card links to Settings instead of a no-op retry.
            if case .authenticationFailed = error {
                SettingsLink { Text("Ouvrir les réglages") }
                    .buttonStyle(.omniLink)
            } else {
                Button(error.retryActionLabel, action: retryAction)
                    .buttonStyle(.omniLink)
            }
        }
        .padding(14)
        .background(OmniTheme.paperMuted)
        .overlay(alignment: .leading) {
            Rectangle().fill(error.codeColor).frame(width: 3)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

/// A real countdown from the server's own `Retry-After` value — never a
/// fabricated animation. Purely informational: it doesn't auto-retry, the
/// user still taps the retry button once it reaches zero.
private struct RateLimitCountdown: View {
    let totalSeconds: Double
    @State private var remaining: Double
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(totalSeconds: Double) {
        self.totalSeconds = totalSeconds
        _remaining = State(initialValue: totalSeconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(OmniTheme.hairline)
                    Rectangle()
                        .fill(OmniTheme.warning)
                        .frame(width: geometry.size.width * fractionRemaining)
                }
            }
            .frame(height: 4)

            Text(remaining > 0 ? "Nouvelle tentative possible dans \(Int(remaining))s" : "Prêt à réessayer")
                .font(OmniTheme.mono(9))
                .foregroundStyle(OmniTheme.inkSoft)
        }
        .onReceive(timer) { _ in
            if remaining > 0 { remaining -= 1 }
        }
    }

    private var fractionRemaining: CGFloat {
        guard totalSeconds > 0 else { return 0 }
        return CGFloat(max(remaining, 0) / totalSeconds)
    }
}
