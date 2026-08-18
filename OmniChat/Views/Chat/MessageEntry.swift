import SwiftUI

/// Each turn is set in its own register: a request reads as a quoted,
/// italic aside in the margin; a response reads as flowing serif prose —
/// the print-shop's substitute for chat bubbles.
struct MessageEntry: View {
    let message: Message
    var isGenerating: Bool = false
    var pendingKind: MediaKind? = nil

    var body: some View {
        if message.role == "user" {
            requestBlock
        } else {
            responseBlock
        }
    }

    /// The mockup's initial-letter "lettrine" — the first character set large
    /// and in the warm accent, the rest of the response as normal serif
    /// prose. SwiftUI has no CSS-style float, so this doesn't wrap text
    /// around the tall letter across multiple lines like the mockup does;
    /// it's a Text-concatenation approximation, not a pixel-exact port.
    private func dropCapText(_ content: String) -> Text {
        guard let first = content.first else { return Text(content) }
        return Text(String(first))
            .font(OmniTheme.serif(32, weight: .semibold))
            .foregroundStyle(OmniTheme.warning)
            + Text(String(content.dropFirst()))
                .font(OmniTheme.serif(15))
                .foregroundStyle(OmniTheme.ink)
    }

    private var requestBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            OmniTheme.label("Demande", size: 10, color: OmniTheme.inkSoft)
            Text(message.content)
                .font(OmniTheme.serif(15).italic())
                .foregroundStyle(OmniTheme.ink.opacity(0.85))
        }
        .padding(.leading, 14)
        .padding(.vertical, 2)
        .overlay(alignment: .leading) {
            Rectangle().fill(OmniTheme.accent).frame(width: 3)
        }
    }

    /// A real tool call OmniChat executed itself for this turn — name,
    /// raw arguments, and the actual result, never OmniRoute's MCP catalog
    /// (unreachable for a self-hosted remote instance; see
    /// `OmniRouteClient+MCP.swift`).
    private func toolCallCard(name: String, arguments: String?, result: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 9, weight: .semibold))
                Text(name)
                    .font(OmniTheme.mono(10, weight: .semibold))
            }
            .foregroundStyle(OmniTheme.accent)
            if let arguments, !arguments.isEmpty {
                Text(arguments)
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.inkSoft)
            }
            if let result {
                Text(result)
                    .font(OmniTheme.mono(10))
                    .foregroundStyle(OmniTheme.ink)
                    .lineLimit(4)
            }
        }
        .padding(10)
        .background(OmniTheme.paperMuted)
        .overlay(alignment: .leading) {
            Rectangle().fill(OmniTheme.accent).frame(width: 2)
        }
    }

    private var responseBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(message.isIncomplete ? OmniTheme.warning : OmniTheme.success)
                    .frame(width: 6, height: 6)
                OmniTheme.label("Réponse", size: 10, color: OmniTheme.inkSoft)
            }
            if let toolName = message.toolName {
                toolCallCard(name: toolName, arguments: message.toolArguments, result: message.toolResult)
            }
            if let mediaItem = message.mediaItem {
                MediaContentView(mediaItem: mediaItem)
                Text(mediaItem.prompt)
                    .font(OmniTheme.serif(13).italic())
                    .foregroundStyle(OmniTheme.inkSoft)
            } else if message.content.isEmpty {
                if isGenerating {
                    GeneratingIndicatorView(kind: pendingKind)
                } else {
                    Text("…")
                        .font(OmniTheme.serif(15))
                        .foregroundStyle(OmniTheme.ink)
                }
            } else {
                dropCapText(message.content)
                    .lineSpacing(5)
            }
            if let telemetrySummary = message.telemetrySummary {
                Text(telemetrySummary)
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.inkSoft)
            }
        }
    }
}
