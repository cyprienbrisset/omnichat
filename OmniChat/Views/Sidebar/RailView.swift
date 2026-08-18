import SwiftUI

/// The dark, fixed-ink strip carrying the app's identity mark, primary
/// navigation action, sidebar mode switcher, and settings entry point.
struct RailView: View {
    @Binding var mode: SidebarMode
    let isGallerySelected: Bool
    let isMemorySelected: Bool
    let isMCPSelected: Bool
    let catalogSummary: CatalogSummary?
    let onNewConversation: () -> Void
    let onSelectGallery: () -> Void
    let onSelectMemory: () -> Void
    let onSelectMCP: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            // The real macOS traffic lights already occupy this corner once
            // the window uses a hidden title bar — no decorative stand-ins.
            Spacer().frame(height: 28)

            Text("O")
                .font(OmniTheme.serif(14, weight: .semibold))
                .foregroundStyle(OmniTheme.railText)
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(OmniTheme.railText.opacity(0.4), lineWidth: 1)
                )

            Button(action: onNewConversation) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OmniTheme.railText)
            }
            .buttonStyle(.plain)
            .help("Nouvelle conversation")

            Rectangle().fill(OmniTheme.railText.opacity(0.2)).frame(width: 20, height: 1)

            ForEach([SidebarMode.conversations, .archived, .trash]) { candidate in
                Button {
                    mode = candidate
                } label: {
                    Image(systemName: candidate.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            !isGallerySelected && !isMemorySelected && !isMCPSelected && mode == candidate
                                ? OmniTheme.accent : OmniTheme.railText.opacity(0.7)
                        )
                }
                .buttonStyle(.plain)
                .help(candidate.title)
            }

            Button(action: onSelectGallery) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isGallerySelected ? OmniTheme.accent : OmniTheme.railText.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Galerie")

            Button(action: onSelectMemory) {
                Image(systemName: "brain")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isMemorySelected ? OmniTheme.accent : OmniTheme.railText.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Mémoire")

            Button(action: onSelectMCP) {
                Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isMCPSelected ? OmniTheme.accent : OmniTheme.railText.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Serveur MCP")

            Spacer()

            if let catalogSummary {
                Text("omniroute · \(catalogSummary.providerCount) fournisseurs")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(OmniTheme.railText.opacity(0.42))
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .frame(width: 20)
            }

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(OmniTheme.railText.opacity(0.75))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
        }
        // Wide enough to fully contain macOS's real traffic-light cluster
        // (~76pt from the left edge) so the green button doesn't spill onto
        // the sidebar's cream background behind it.
        .frame(width: 84)
        .frame(maxHeight: .infinity)
        .background(OmniTheme.rail)
    }
}
