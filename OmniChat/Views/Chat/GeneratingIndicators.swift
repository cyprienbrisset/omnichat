import SwiftUI

/// What's shown in place of the response while it's still generating —
/// the shape of the wait matches what's actually being waited for, rather
/// than one static ellipsis for every request kind.
struct GeneratingIndicatorView: View {
    let kind: MediaKind?

    var body: some View {
        HStack(spacing: 8) {
            switch kind {
            case nil:
                TypingDotsView()
            case .image:
                PulsingIconView(systemImage: "photo")
            case .video:
                PulsingIconView(systemImage: "video")
            case .music, .speech:
                EqualizerBarsView()
            }
            Text(label)
                .font(OmniTheme.mono(10))
                .foregroundStyle(OmniTheme.inkSoft)
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

/// A slow breathing icon, for single-shot image/video generation — there's
/// no natural "wave" to animate for a one-off request, so it just pulses.
struct PulsingIconView: View {
    let systemImage: String
    @State private var isPulsing = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(OmniTheme.accent)
            .opacity(isPulsing ? 1 : 0.35)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

/// An animated equalizer, for music/speech generation.
struct EqualizerBarsView: View {
    @State private var heights: [CGFloat] = [5, 9, 13, 8, 5]
    private let timer = Timer.publish(every: 0.28, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(heights.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(OmniTheme.accent)
                    .frame(width: 3, height: heights[index])
            }
        }
        .frame(height: 14, alignment: .bottom)
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.28)) {
                heights = heights.map { _ in CGFloat.random(in: 4...14) }
            }
        }
    }
}
