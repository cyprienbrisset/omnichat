import SwiftUI
import AppKit

struct MenuBarChatView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(OmniTheme.accent)
                Text("OmniChat")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            Text("Ouvre la fenêtre principale pour discuter.")
                .font(.system(size: 11))
                .foregroundStyle(OmniTheme.secondaryText)
            Button("Ouvrir OmniChat") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .buttonStyle(.omniPrimary)
            SettingsLink {
                Text("Réglages…")
                    .font(.system(size: 12))
                    .foregroundStyle(OmniTheme.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 220)
    }
}
