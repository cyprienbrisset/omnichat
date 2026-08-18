import SwiftUI
import AppKit

struct MenuBarChatView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OmniChat").font(.headline)
            Text("Ouvre la fenêtre principale pour discuter.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Ouvrir OmniChat") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            SettingsLink {
                Text("Réglages…")
            }
        }
        .padding()
        .frame(width: 220)
    }
}
