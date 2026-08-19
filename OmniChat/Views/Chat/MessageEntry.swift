import SwiftUI
import AppKit

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

    /// What a message's copy button actually copies — the real text a user
    /// would want on their clipboard, in priority order. `nil` hides the
    /// button rather than copying nothing.
    private var copyableText: String? {
        if !message.content.isEmpty { return message.content }
        if let mediaItem = message.mediaItem { return mediaItem.prompt }
        if let toolResult = message.toolResult { return toolResult }
        return nil
    }

    private func copyButton(text: String) -> some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(OmniTheme.inkSoft)
        }
        .buttonStyle(.plain)
        .help("Copier")
    }

    private var requestBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                OmniTheme.label("Demande", size: 10, color: OmniTheme.inkSoft)
                copyButton(text: message.content)
            }
            Text(message.content)
                .font(OmniTheme.serif(15).italic())
                .foregroundStyle(OmniTheme.ink.opacity(0.85))
                .textSelection(.enabled)
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
                    .textSelection(.enabled)
            }
            if let result {
                ToolResultText(result: result)
            }
        }
        .padding(10)
        .background(OmniTheme.paperMuted)
        .overlay(alignment: .leading) {
            Rectangle().fill(OmniTheme.accent).frame(width: 2)
        }
    }

    /// The model that actually answered — read from the same routing
    /// telemetry as `telemetrySummary` (`X-OmniRoute-*` response headers),
    /// never a guess: `"auto → openai/gpt-4o"` when routed automatically,
    /// just `"openai/gpt-4o"` when a specific model was requested directly.
    /// `nil` (not shown) when this response carries no routing telemetry.
    private var respondingModel: String? {
        switch (message.routingStrategy, message.routingProvider) {
        case let (strategy?, provider?) where strategy != "single":
            return "\(strategy) → \(provider)"
        case (_, let provider?):
            return provider
        case (let strategy?, nil):
            return strategy
        default:
            return nil
        }
    }

    private var responseBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(message.isIncomplete ? OmniTheme.warning : OmniTheme.success)
                    .frame(width: 6, height: 6)
                OmniTheme.label("Réponse", size: 10, color: OmniTheme.inkSoft)
                if let respondingModel {
                    Text(respondingModel)
                        .font(OmniTheme.mono(9, weight: .semibold))
                        .foregroundStyle(OmniTheme.accent)
                }
                if let copyableText {
                    copyButton(text: copyableText)
                }
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
                MarkdownContentView(blocks: MarkdownParser.parse(message.content), appliesDropCap: true)
                    .textSelection(.enabled)
            }
            if let telemetrySummary = message.telemetrySummary {
                Text(telemetrySummary)
                    .font(OmniTheme.mono(9))
                    .foregroundStyle(OmniTheme.inkSoft)
            }
        }
    }
}

/// A tool result can be arbitrarily long (a full search passage, raw JSON…).
/// Collapsing it with a hard `lineLimit` silently drops real data behind an
/// ellipsis, which reads as a bug rather than a design choice. This instead
/// collapses only past a real length threshold, with an explicit toggle that
/// always has access to the full, untruncated text.
private struct ToolResultText: View {
    let result: String
    @State private var isExpanded = false

    private static let collapseThreshold = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result)
                .font(OmniTheme.mono(10))
                .foregroundStyle(OmniTheme.ink)
                .textSelection(.enabled)
                .lineLimit(isExpanded || result.count <= Self.collapseThreshold ? nil : 4)
            if result.count > Self.collapseThreshold {
                Button(isExpanded ? "Réduire" : "Afficher tout") {
                    isExpanded.toggle()
                }
                .buttonStyle(.omniLink)
            }
        }
    }
}
