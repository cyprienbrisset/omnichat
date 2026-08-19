import SwiftUI

/// The dark, fixed-ink strip carrying the app's identity mark, primary
/// navigation action, sidebar mode switcher, and settings entry point.
struct RailView: View {
    @Binding var mode: SidebarMode
    let isGallerySelected: Bool
    let isMemorySelected: Bool
    let isMCPSelected: Bool
    let isRAGSelected: Bool
    let isComparisonSelected: Bool
    let isFusionSelected: Bool
    let isAdminSelected: Bool
    /// Only true once the active key is confirmed to carry management
    /// scope — this entry point changes the connected server's real
    /// configuration, so it doesn't appear at all for a key that can't
    /// use it (rather than appearing and failing with an auth error).
    let showsAdmin: Bool
    let catalogSummary: CatalogSummary?
    let onNewConversation: () -> Void
    let onSelectGallery: () -> Void
    let onSelectMemory: () -> Void
    let onSelectMCP: () -> Void
    let onSelectRAG: () -> Void
    let onSelectComparison: () -> Void
    let onSelectFusion: () -> Void
    let onSelectAdmin: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            // The real macOS traffic lights already occupy this corner once
            // the window uses a hidden title bar — no decorative stand-ins.
            Spacer().frame(height: 28)

            Image("BrandMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(OmniTheme.railText)
                .padding(5)
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
                            !isGallerySelected && !isMemorySelected && !isMCPSelected && !isRAGSelected
                                && !isComparisonSelected && !isFusionSelected && !isAdminSelected && mode == candidate
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

            Button(action: onSelectRAG) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isRAGSelected ? OmniTheme.accent : OmniTheme.railText.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Recherche locale")

            Button(action: onSelectComparison) {
                Image(systemName: "square.split.2x1")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isComparisonSelected ? OmniTheme.accent : OmniTheme.railText.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Comparaison")

            Button(action: onSelectFusion) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isFusionSelected ? OmniTheme.accent : OmniTheme.railText.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Fusion")

            if showsAdmin {
                Button(action: onSelectAdmin) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isAdminSelected ? OmniTheme.accent : OmniTheme.railText.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Administration")
            }

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
