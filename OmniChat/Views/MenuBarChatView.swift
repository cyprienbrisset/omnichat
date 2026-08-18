import SwiftUI
import AppKit

struct MenuBarChatView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            }

            Rectangle().fill(OmniTheme.hairline).frame(height: 1)

            HStack(spacing: 5) {
                Circle().fill(OmniTheme.success).frame(width: 5, height: 5)
                Text(appEnvironment.activeProfile.baseURL.host ?? appEnvironment.activeProfile.baseURL.absoluteString)
                    .font(OmniTheme.mono(10))
                    .foregroundStyle(OmniTheme.inkSoft)
                    .lineLimit(1)
            }

            Text("Ouvre la fenêtre principale pour reprendre une conversation.")
                .font(OmniTheme.serif(11).italic())
                .foregroundStyle(OmniTheme.inkSoft)

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
        .frame(width: 240)
        .background(OmniTheme.paper)
    }
}
