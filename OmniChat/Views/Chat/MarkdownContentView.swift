import SwiftUI

/// Renders a message's parsed Markdown blocks as prose — headings step up in
/// size, `---` becomes a hairline rule, list markers are kept verbatim, and
/// every text block goes through `Text(LocalizedStringKey:)` so SwiftUI's
/// native inline Markdown (`**bold**`, `*italic*`, `` `code` ``, links) just
/// works without a custom inline parser.
struct MarkdownContentView: View {
    let blocks: [MarkdownBlock]
    /// The mockup's "lettrine" — applied only to the first paragraph, and
    /// only when that paragraph doesn't open on a Markdown special character
    /// (an emphasis marker split at the drop cap would break the pairing).
    var appliesDropCap: Bool = false

    private var firstParagraphIndex: Int? {
        blocks.firstIndex { if case .paragraph = $0 { return true } else { return false } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                blockView(block, isFirstParagraph: appliesDropCap && index == firstParagraphIndex)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock, isFirstParagraph: Bool) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(LocalizedStringKey(text))
                .font(OmniTheme.serif(headingSize(level), weight: .semibold))
                .foregroundStyle(OmniTheme.ink)
        case .rule:
            Rectangle().fill(OmniTheme.hairline).frame(height: 1)
        case .codeBlock(let text):
            Text(text)
                .font(OmniTheme.mono(12))
                .foregroundStyle(OmniTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(OmniTheme.paperMuted)
                .textSelection(.enabled)
        case .listItem(let marker, let text):
            HStack(alignment: .top, spacing: 8) {
                Text(marker)
                    .font(OmniTheme.serif(15, weight: .semibold))
                    .foregroundStyle(OmniTheme.inkSoft)
                Text(LocalizedStringKey(text))
                    .font(OmniTheme.serif(15))
                    .foregroundStyle(OmniTheme.ink)
                    .lineSpacing(4)
            }
        case .paragraph(let text):
            if isFirstParagraph {
                dropCapText(text)
            } else {
                Text(LocalizedStringKey(text))
                    .font(OmniTheme.serif(15))
                    .foregroundStyle(OmniTheme.ink)
                    .lineSpacing(5)
            }
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 22
        case 2: return 19
        case 3: return 17
        default: return 16
        }
    }

    /// Falls back to plain (markdown-aware) rendering when the paragraph
    /// opens on a character that isn't a letter/number — e.g. an emphasis
    /// marker like `**bold**` at the very start, where lifting off the first
    /// literal character would leave an unpaired `*` behind.
    private func dropCapText(_ content: String) -> Text {
        guard let first = content.first, first.isLetter || first.isNumber else {
            return Text(LocalizedStringKey(content))
                .font(OmniTheme.serif(15))
                .foregroundStyle(OmniTheme.ink)
        }
        return Text(String(first))
            .font(OmniTheme.serif(32, weight: .semibold))
            .foregroundStyle(OmniTheme.warning)
            + Text(LocalizedStringKey(String(content.dropFirst())))
                .font(OmniTheme.serif(15))
                .foregroundStyle(OmniTheme.ink)
    }
}
