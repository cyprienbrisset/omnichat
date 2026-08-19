import SwiftUI
import AVKit

/// The enlarged view opened by tapping a generated media item — same real
/// file `MediaContentView` renders inline, just given the room to actually
/// look at (or listen to) properly, plus the one action that only makes
/// sense here: exporting a copy.
struct MediaDetailView: View {
    let mediaItem: MediaItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
            largeContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
        }
        .frame(minWidth: 480, minHeight: 360)
        .background(OmniTheme.paper)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                OmniTheme.label(mediaItem.kind, size: 9, color: OmniTheme.inkSoft)
                Text(mediaItem.prompt)
                    .font(OmniTheme.serif(13).italic())
                    .foregroundStyle(OmniTheme.ink)
                    .lineLimit(3)
            }
            Spacer()
            Button("Télécharger") {
                MediaExporter.exportCopy(of: mediaItem.fileURL, suggestedName: mediaItem.fileURL.lastPathComponent)
            }
            .buttonStyle(.omniLink)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(OmniTheme.inkSoft)
        }
        .padding(16)
    }

    @ViewBuilder
    private var largeContent: some View {
        switch mediaItem.kind {
        case "image":
            if let nsImage = NSImage(contentsOf: mediaItem.fileURL) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
            } else {
                unavailable
            }
        case "video":
            VideoPlayer(player: AVPlayer(url: mediaItem.fileURL))
        case "music", "speech":
            VideoPlayer(player: AVPlayer(url: mediaItem.fileURL))
                .frame(height: 80)
        default:
            unavailable
        }
    }

    private var unavailable: some View {
        Text("Média indisponible")
            .font(OmniTheme.mono(11))
            .foregroundStyle(OmniTheme.inkSoft)
    }
}
