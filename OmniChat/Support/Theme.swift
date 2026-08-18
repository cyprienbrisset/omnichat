import SwiftUI
import AppKit

/// OmniChat's design language — inspired by OmniRoute's own brand identity:
/// a dark, technical, terminal-flavored look with a coral accent, monospace
/// for anything technical, bold display type for headers, and a subtle
/// dot-grid texture. Centralized here so every view draws from the same
/// palette instead of hardcoding colors/fonts independently.
enum OmniTheme {
    static let accent = Color(
        light: NSColor(calibratedRed: 0.90, green: 0.17, blue: 0.32, alpha: 1),
        dark: NSColor(calibratedRed: 1.00, green: 0.24, blue: 0.39, alpha: 1)
    )

    static let success = Color(
        light: NSColor(calibratedRed: 0.09, green: 0.64, blue: 0.29, alpha: 1),
        dark: NSColor(calibratedRed: 0.13, green: 0.77, blue: 0.37, alpha: 1)
    )

    static let canvasBackground = Color(
        light: NSColor(calibratedWhite: 0.98, alpha: 1),
        dark: NSColor(calibratedRed: 0.043, green: 0.043, blue: 0.063, alpha: 1)
    )

    static let cardBackground = Color(
        light: NSColor(calibratedWhite: 1.0, alpha: 1),
        dark: NSColor(calibratedRed: 0.086, green: 0.086, blue: 0.114, alpha: 1)
    )

    static let cardBorder = Color(
        light: NSColor(calibratedWhite: 0.89, alpha: 1),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.09)
    )

    static let secondaryText = Color(
        light: NSColor(calibratedWhite: 0.42, alpha: 1),
        dark: NSColor(calibratedWhite: 0.63, alpha: 1)
    )

    static func mono(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    @ViewBuilder
    static func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(OmniTheme.accent)
    }
}

extension Color {
    /// An adaptive color that resolves against the current appearance,
    /// mirroring how OmniRoute leans hard into dark mode while still
    /// behaving like a native Mac app in light mode.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

/// Pill-shaped, coral-filled primary action button — the one button style
/// every prominent action (send, create, save) shares.
struct OmniPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(OmniTheme.accent.opacity(configuration.isPressed ? 0.8 : 1))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }
}

extension ButtonStyle where Self == OmniPrimaryButtonStyle {
    static var omniPrimary: OmniPrimaryButtonStyle { OmniPrimaryButtonStyle() }
}

/// A very subtle dot-grid texture, echoing the backdrop on omniroute.online.
/// Purely decorative — never intercepts hit testing.
struct OmniDotGridBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 22
            let dotSize: CGFloat = 1.4
            let dotColor = GraphicsContext.Shading.color(OmniTheme.secondaryText.opacity(0.12))
            var x: CGFloat = spacing / 2
            while x < size.width {
                var y: CGFloat = spacing / 2
                while y < size.height {
                    let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: rect), with: dotColor)
                    y += spacing
                }
                x += spacing
            }
        }
        .allowsHitTesting(false)
    }
}
