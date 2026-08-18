import SwiftUI

struct PersistenceErrorBanner: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OmniTheme.label("Enregistrement", size: 10, color: OmniTheme.warning)
            Text(message)
                .font(OmniTheme.serif(13))
                .foregroundStyle(OmniTheme.ink)
        }
        .padding(14)
        .background(OmniTheme.paperMuted)
        .overlay(alignment: .leading) {
            Rectangle().fill(OmniTheme.warning).frame(width: 3)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}
