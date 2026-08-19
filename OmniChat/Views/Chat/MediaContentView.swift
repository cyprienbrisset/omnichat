import SwiftUI
import AVKit

/// Renders a generated media item inline — reused at gallery-cell scale by
/// `GalleryView` (frame size is the caller's responsibility, not baked in
/// here beyond a sensible chat-inline default). A corner chip always offers
/// "enlarge" and "download"; images are additionally tappable anywhere,
/// since (unlike video/audio) they have no native control surface a tap
/// gesture would fight with.
struct MediaContentView: View {
    let mediaItem: MediaItem
    @State private var showingDetail = false

    var body: some View {
        Group {
            switch mediaItem.kind {
            case "image":
                if let nsImage = NSImage(contentsOf: mediaItem.fileURL) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 360)
                        .contentShape(Rectangle())
                        .onTapGesture { showingDetail = true }
                } else {
                    unavailable
                }
            case "video":
                VideoPlayer(player: AVPlayer(url: mediaItem.fileURL))
                    .frame(width: 360, height: 220)
            case "music", "speech":
                VideoPlayer(player: AVPlayer(url: mediaItem.fileURL))
                    .frame(width: 320, height: 50)
            default:
                unavailable
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(OmniTheme.hairline, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if isAvailable {
                controlsChip
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .sheet(isPresented: $showingDetail) {
            MediaDetailView(mediaItem: mediaItem)
        }
    }

    private var controlsChip: some View {
        HStack(spacing: 8) {
            Button {
                showingDetail = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .help("Agrandir")

            Button {
                MediaExporter.exportCopy(of: mediaItem.fileURL, suggestedName: mediaItem.fileURL.lastPathComponent)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 9, weight: .semibold))
            }
            .help("Télécharger")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.55), in: Capsule())
        .padding(6)
    }

    /// Nothing to enlarge or export when the file is missing or the kind
    /// isn't one this view actually knows how to render.
    private var isAvailable: Bool {
        switch mediaItem.kind {
        case "image": return NSImage(contentsOf: mediaItem.fileURL) != nil
        case "video", "music", "speech": return FileManager.default.fileExists(atPath: mediaItem.fileURL.path)
        default: return false
        }
    }

    private var unavailable: some View {
        Text("Média indisponible")
            .font(OmniTheme.mono(11))
            .foregroundStyle(OmniTheme.inkSoft)
            .padding(12)
    }
}
