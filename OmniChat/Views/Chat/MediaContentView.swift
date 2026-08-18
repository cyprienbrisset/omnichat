import SwiftUI
import AVKit

/// Renders a generated media item inline — reused at gallery-cell scale by
/// `GalleryView` (frame size is the caller's responsibility, not baked in
/// here beyond a sensible chat-inline default).
struct MediaContentView: View {
    let mediaItem: MediaItem

    var body: some View {
        Group {
            switch mediaItem.kind {
            case "image":
                if let nsImage = NSImage(contentsOf: mediaItem.fileURL) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 360)
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
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var unavailable: some View {
        Text("Média indisponible")
            .font(OmniTheme.mono(11))
            .foregroundStyle(OmniTheme.inkSoft)
            .padding(12)
    }
}
