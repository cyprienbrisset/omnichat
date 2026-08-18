import SwiftUI

/// What's shown in place of the response while it's still generating —
/// the shape of the wait matches what's actually being waited for, rather
/// than one static ellipsis for every request kind.
struct GeneratingIndicatorView: View {
    let kind: MediaKind?

    var body: some View {
        switch kind {
        case nil:
            HStack(spacing: 8) {
                TypingDotsView()
                Text(label)
                    .font(OmniTheme.mono(10))
                    .foregroundStyle(OmniTheme.inkSoft)
            }
        case .image, .video, .music, .speech:
            VStack(alignment: .leading, spacing: 6) {
                MediaSkeletonView(kind: kind!)
                Text(label)
                    .font(OmniTheme.mono(10))
                    .foregroundStyle(OmniTheme.inkSoft)
            }
        }
    }

    private var label: String {
        switch kind {
        case nil: return "Rédaction en cours…"
        case .image: return "Génération de l'image…"
        case .video: return "Génération de la vidéo…"
        case .music: return "Génération de la musique…"
        case .speech: return "Synthèse vocale…"
        }
    }
}

/// The classic three-dot "typing" indicator, for plain text responses.
struct TypingDotsView: View {
    @State private var activeIndex = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(OmniTheme.inkSoft)
                    .frame(width: 6, height: 6)
                    .opacity(activeIndex == index ? 1 : 0.25)
            }
        }
        .onReceive(timer) { _ in
            activeIndex = (activeIndex + 1) % 3
        }
    }
}

/// A placeholder shaped like the media that's actually being generated
/// (same footprint `MediaContentView` renders once the real file lands),
/// with a soft shimmer sweeping across it — reads as "something real is
/// being built here" rather than a generic spinner unrelated to the result.
struct MediaSkeletonView: View {
    let kind: MediaKind
    @State private var shimmerX: CGFloat = -0.6

    private var size: CGSize {
        switch kind {
        case .image: CGSize(width: 320, height: 240)
        case .video: CGSize(width: 360, height: 220)
        case .music, .speech: CGSize(width: 320, height: 50)
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(OmniTheme.paperMuted)
            .frame(width: size.width, height: size.height)
            .overlay {
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [.clear, OmniTheme.ink.opacity(0.08), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.5)
                    .offset(x: shimmerX * geometry.size.width)
                }
                .clipped()
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(OmniTheme.hairline, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    shimmerX = 1.6
                }
            }
    }
}
