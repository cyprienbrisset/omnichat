import SwiftUI
import AppKit

/// OmniChat's design language — an "atelier d'imprimerie" (print-shop) aesthetic:
/// warm paper backgrounds, serif prose, tracked-out uppercase monospace labels,
/// hairline rules, and a single ink-black surface reserved for the rail and
/// primary actions. Centralized here so every view draws from the same palette
/// instead of hardcoding colors/fonts independently.
enum OmniTheme {
    // MARK: Brand charter (docs/brand/) — the three canonical swatches from
    // the OmniChat logo sheet. Every color below derives from these three
    // values rather than restating its own hex, so the palette stays in
    // sync with the brand assets by construction.
    private static let noirPresse = NSColor(calibratedRed: CGFloat(0x0E) / 255, green: CGFloat(0x0E) / 255, blue: CGFloat(0x0E) / 255, alpha: 1)
    private static let ivoirePapier = NSColor(calibratedRed: CGFloat(0xF7) / 255, green: CGFloat(0xF4) / 255, blue: CGFloat(0xEE) / 255, alpha: 1)
    private static let orMat = NSColor(calibratedRed: CGFloat(0xC9) / 255, green: CGFloat(0xA9) / 255, blue: CGFloat(0x6E) / 255, alpha: 1)

    // MARK: Paper (backgrounds)

    static let paper = Color(light: ivoirePapier, dark: noirPresse)

    static let paperMuted = Color(
        light: NSColor(calibratedRed: 0.937, green: 0.918, blue: 0.874, alpha: 1),
        dark: NSColor(calibratedRed: 0.086, green: 0.082, blue: 0.063, alpha: 1)
    )

    // MARK: Ink (text)

    static let ink = Color(light: noirPresse, dark: ivoirePapier)

    static let inkSoft = ink.opacity(0.55)

    static let hairline = ink.opacity(0.16)

    /// The rail, menu-bar header, and filled primary buttons always sit on
    /// ink-black — a fixed "printed" surface rather than one that inverts
    /// with the appearance, echoing how black ink stays black on any page.
    static let rail = Color(nsColor: noirPresse)
    static let railText = Color(nsColor: ivoirePapier)

    // MARK: Accents

    /// "Or Mat" from the brand charter — a single fixed value (not
    /// light/dark-adaptive) since a matte-gold accent is meant to read the
    /// same way against both paper and ink, like foil on a printed page.
    static let accent = Color(nsColor: orMat)

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

    /// The brand charter specifies Spectral for prose/titles (Romie and
    /// Canela, the display faces used for the wordmark itself, are
    /// commercial and not bundled here — see docs/brand/). Spectral ships
    /// under the SIL Open Font License as static per-weight files in
    /// `Resources/Fonts/`, registered at launch via the bundle's
    /// `ATSApplicationFontsPath`; picking the exact PostScript name per
    /// weight (rather than `Font.custom("Spectral", ...).weight(...)`)
    /// avoids depending on AppKit's family+trait resolution for the base
    /// weight — `.italic()` at call sites still relies on it, verified
    /// separately to correctly resolve e.g. Spectral-Bold + italic trait
    /// to Spectral-BoldItalic.
    static func serif(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        let postScriptName: String
        switch weight {
        case .medium: postScriptName = "Spectral-Medium"
        case .semibold: postScriptName = "Spectral-SemiBold"
        case .bold, .heavy, .black: postScriptName = "Spectral-Bold"
        default: postScriptName = "Spectral-Regular"
        }
        return .custom(postScriptName, size: size)
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
