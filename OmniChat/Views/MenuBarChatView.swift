import SwiftUI
import AppKit

struct MenuBarChatView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OmniChat").font(.headline)
            Text("Ouvre la fenêtre principale pour discuter.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Ouvrir OmniChat") {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where !window.title.isEmpty {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
        .padding()
        .frame(width: 220)
    }
}
