import SwiftUI
import AppKit

/// OmniChat's design language — an "atelier d'imprimerie" (print-shop) aesthetic:
/// warm paper backgrounds, serif prose, tracked-out uppercase monospace labels,
/// hairline rules, and a single ink-black surface reserved for the rail and
/// primary actions. Centralized here so every view draws from the same palette
/// instead of hardcoding colors/fonts independently.
enum OmniTheme {
    // MARK: Paper (backgrounds)

    static let paper = Color(
        light: NSColor(calibratedRed: 0.961, green: 0.937, blue: 0.886, alpha: 1),
        dark: NSColor(calibratedRed: 0.110, green: 0.102, blue: 0.090, alpha: 1)
    )

    static let paperMuted = Color(
        light: NSColor(calibratedRed: 0.929, green: 0.898, blue: 0.827, alpha: 1),
        dark: NSColor(calibratedRed: 0.141, green: 0.129, blue: 0.098, alpha: 1)
    )

    // MARK: Ink (text)

    static let ink = Color(
        light: NSColor(calibratedRed: 0.098, green: 0.082, blue: 0.071, alpha: 1),
        dark: NSColor(calibratedRed: 0.949, green: 0.925, blue: 0.867, alpha: 1)
    )

    static let inkSoft = Color(
        light: NSColor(calibratedRed: 0.098, green: 0.082, blue: 0.071, alpha: 0.55),
        dark: NSColor(calibratedRed: 0.949, green: 0.925, blue: 0.867, alpha: 0.55)
    )

    static let hairline = Color(
        light: NSColor(calibratedRed: 0.098, green: 0.082, blue: 0.071, alpha: 0.16),
        dark: NSColor(calibratedRed: 0.949, green: 0.925, blue: 0.867, alpha: 0.16)
    )

    /// The rail, menu-bar header, and filled primary buttons always sit on
    /// ink-black — a fixed "printed" surface rather than one that inverts
    /// with the appearance, echoing how black ink stays black on any page.
    static let rail = Color(nsColor: NSColor(calibratedRed: 0.098, green: 0.082, blue: 0.071, alpha: 1))
    static let railText = Color(nsColor: NSColor(calibratedRed: 0.961, green: 0.937, blue: 0.886, alpha: 1))

    // MARK: Accents

    static let accent = Color(
        light: NSColor(calibratedRed: 0.231, green: 0.435, blue: 0.878, alpha: 1),
        dark: NSColor(calibratedRed: 0.431, green: 0.576, blue: 0.933, alpha: 1)
    )

    static let success = Color(
        light: NSColor(calibratedRed: 0.184, green: 0.490, blue: 0.310, alpha: 1),
        dark: NSColor(calibratedRed: 0.373, green: 0.655, blue: 0.463, alpha: 1)
    )

    static let warning = Color(
        light: NSColor(calibratedRed: 0.702, green: 0.329, blue: 0.118, alpha: 1),
        dark: NSColor(calibratedRed: 0.851, green: 0.478, blue: 0.267, alpha: 1)
    )

    static let danger = Color(
        light: NSColor(calibratedRed: 0.788, green: 0.345, blue: 0.310, alpha: 1),
        dark: NSColor(calibratedRed: 0.878, green: 0.467, blue: 0.431, alpha: 1)
    )

    // MARK: Backwards-compatible aliases (kept during the print-shop restyle)

    static let secondaryText = inkSoft
    static let canvasBackground = paper
    static let cardBackground = paperMuted
    static let cardBorder = hairline

    // MARK: Typography

    static func serif(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func mono(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// A tracked-out, uppercase monospace label — the recurring "printer's
    /// caption" motif used for section headers, badges, and metadata.
    @ViewBuilder
    static func label(_ text: String, size: CGFloat = 11, color: Color = OmniTheme.accent) -> some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(color)
    }

    /// Retained for call sites not yet migrated to `label(_:)`.
    @ViewBuilder
    static func eyebrow(_ text: String) -> some View {
        label(text)
    }
}

extension Color {
    /// An adaptive color that resolves against the current appearance.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

/// Filled, ink-black primary action — a small-radius rectangle rather than a
/// pill, matching the print-shop's squared-off, letterpress-adjacent buttons.
struct OmniPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .tracking(0.6)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(OmniTheme.rail.opacity(configuration.isPressed ? 0.8 : 1))
            .foregroundStyle(OmniTheme.railText)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

extension ButtonStyle where Self == OmniPrimaryButtonStyle {
    static var omniPrimary: OmniPrimaryButtonStyle { OmniPrimaryButtonStyle() }
}

/// The circular ink-black button reserved for the composer's send action.
struct OmniIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .frame(width: 34, height: 34)
            .background(OmniTheme.rail.opacity(configuration.isPressed ? 0.8 : 1))
            .foregroundStyle(OmniTheme.railText)
            .clipShape(Circle())
    }
}

extension ButtonStyle where Self == OmniIconButtonStyle {
    static var omniIcon: OmniIconButtonStyle { OmniIconButtonStyle() }
}

/// A quiet, underlined text action — the print-shop's substitute for a
/// bordered secondary button (settings links, "réessayer", etc.).
struct OmniLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .tracking(1.0)
            .foregroundStyle(OmniTheme.ink.opacity(configuration.isPressed ? 0.5 : 0.8))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(OmniTheme.hairline)
                    .frame(height: 1)
                    .offset(y: 2)
            }
    }
}

extension ButtonStyle where Self == OmniLinkButtonStyle {
    static var omniLink: OmniLinkButtonStyle { OmniLinkButtonStyle() }
}

/// User-facing override for the app's appearance, independent of the macOS
/// system setting.
enum ThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// `nil` lets SwiftUI fall back to the system appearance.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "Système"
        case .light: return "Clair"
        case .dark: return "Sombre"
        }
    }
}

/// A faint repeating diagonal hairline texture, echoing an etching plate.
/// Purely decorative — never intercepts hit testing.
struct OmniPaperTexture: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 5
            let angle = CGFloat.pi * (115.0 / 180.0)
            let direction = CGVector(dx: cos(angle), dy: sin(angle))
            let lineColor = GraphicsContext.Shading.color(OmniTheme.ink.opacity(0.022))
            let diagonal = sqrt(size.width * size.width + size.height * size.height)
            var offset: CGFloat = -diagonal
            while offset < diagonal {
                var path = Path()
                let mid = CGPoint(x: size.width / 2, y: size.height / 2)
                let normal = CGVector(dx: -direction.dy, dy: direction.dx)
                let base = CGPoint(x: mid.x + normal.dx * offset, y: mid.y + normal.dy * offset)
                let start = CGPoint(x: base.x - direction.dx * diagonal, y: base.y - direction.dy * diagonal)
                let end = CGPoint(x: base.x + direction.dx * diagonal, y: base.y + direction.dy * diagonal)
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path, with: lineColor, lineWidth: 1)
                offset += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

/// Retained alias during the print-shop restyle migration.
typealias OmniDotGridBackground = OmniPaperTexture
