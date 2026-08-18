import SwiftUI
import OmniRouteKit

struct ErrorBannerView: View {
    let error: OmniRouteError
    let retryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OmniTheme.label("Erreur", size: 10, color: OmniTheme.danger)
            HStack(alignment: .top, spacing: 12) {
                Text(error.userMessage)
                    .font(OmniTheme.serif(13))
                    .foregroundStyle(OmniTheme.ink)
                Spacer(minLength: 12)
                Button("Réessayer", action: retryAction)
                    .buttonStyle(.omniLink)
            }
        }
        .padding(14)
        .background(OmniTheme.paperMuted)
        .overlay(alignment: .leading) {
            Rectangle().fill(OmniTheme.danger).frame(width: 3)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}
