import SwiftUI
import SwiftData

/// A grid of every generated media item, filterable by kind — the print-shop
/// counterpart to the mockup's "atelier d'images" contact sheet, built from
/// whatever has actually been generated rather than a staged demo.
struct GalleryView: View {
    @Query(sort: \MediaItem.createdAt, order: .reverse) private var items: [MediaItem]
    @State private var filterKind: MediaKind?

    private var filteredItems: [MediaItem] {
        guard let filterKind else { return items }
        return items.filter { $0.kind == filterKind.rawValue }
    }

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                if filteredItems.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredItems) { item in
                            GalleryCell(item: item)
                        }
                    }
                    .padding(24)
                }
            }
            .background(OmniTheme.paper)
            .background { OmniPaperTexture() }
        }
        .background(OmniTheme.paper)
        .navigationTitle("Galerie")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                OmniTheme.label("Atelier", size: 10, color: OmniTheme.inkSoft)
                Text("Galerie")
                    .font(OmniTheme.serif(24, weight: .semibold))
                    .foregroundStyle(OmniTheme.ink)
            }
            filterBar
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OmniTheme.paper)
        .overlay(alignment: .bottom) {
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 20) {
            filterTag(title: "Tout", isSelected: filterKind == nil) { filterKind = nil }
            ForEach(MediaKind.allCases) { kind in
                filterTag(title: kind.label, isSelected: filterKind == kind) { filterKind = kind }
            }
        }
    }

    private func filterTag(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(isSelected ? OmniTheme.ink : OmniTheme.inkSoft)
                .padding(.bottom, 6)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isSelected ? OmniTheme.accent : Color.clear)
                        .frame(height: 2)
                }
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Aucun média généré")
                .font(OmniTheme.serif(18, weight: .semibold))
                .foregroundStyle(OmniTheme.ink)
            Text("Passe le composeur en mode Image, Vidéo, Musique ou Voix dans une conversation pour en générer un.")
                .font(OmniTheme.serif(13).italic())
                .foregroundStyle(OmniTheme.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .padding(.top, 80)
        .frame(maxWidth: .infinity)
    }
}

private struct GalleryCell: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MediaContentView(mediaItem: item)
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipped()
            OmniTheme.label(item.kind, size: 8, color: OmniTheme.inkSoft)
            Text(item.prompt)
                .font(OmniTheme.serif(12))
                .foregroundStyle(OmniTheme.ink)
                .lineLimit(2)
        }
    }
}
