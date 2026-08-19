import Foundation

/// A block-level element extracted from a chat message's raw Markdown text.
/// Deliberately narrow: headings, rules, fenced code, list items, and
/// paragraphs — the subset that actually shows up in model responses.
/// Inline emphasis (`**bold**`, `*italic*`, `` `code` ``, links) is left
/// inside each block's `text` and rendered later via SwiftUI's native
/// `Text(LocalizedStringKey:)` markdown support, not re-parsed here.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case rule
    case codeBlock(text: String)
    case listItem(marker: String, text: String)
    case paragraph(text: String)
}

/// Splits a message's raw content into block-level Markdown elements.
/// Intentionally simple (no nested blockquotes/tables) — real model output
/// in this app is prose, headings, lists, and the occasional code block.
enum MarkdownParser {
    static func parse(_ content: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = content.components(separatedBy: "\n")
        var paragraphLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(text: paragraphLines.joined(separator: "\n")))
            paragraphLines.removeAll()
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                index += 1
                var codeLines: [String] = []
                while index < lines.count && !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 } // skip the closing fence, if present
                blocks.append(.codeBlock(text: codeLines.joined(separator: "\n")))
                continue
            }

            if isRule(trimmed) {
                flushParagraph()
                blocks.append(.rule)
                index += 1
                continue
            }

            if let (level, text) = headingMatch(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: level, text: text))
                index += 1
                continue
            }

            if let (marker, text) = listItemMatch(trimmed) {
                flushParagraph()
                blocks.append(.listItem(marker: marker, text: text))
                index += 1
                continue
            }

            paragraphLines.append(trimmed)
            index += 1
        }
        flushParagraph()
        return blocks
    }

    /// `---`, `***`, or `___` (optionally spaced out), at least 3 characters.
    private static func isRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        return compact.allSatisfy { $0 == "-" } || compact.allSatisfy { $0 == "*" } || compact.allSatisfy { $0 == "_" }
    }

    /// `# `, `## `, up to `###### ` — a run of 1-6 `#` then a space.
    private static func headingMatch(_ line: String) -> (Int, String)? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == "#" {
            level += 1
            index = line.index(after: index)
        }
        guard level <= 6, index < line.endIndex, line[index] == " " else { return nil }
        let text = line[line.index(after: index)...].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    /// `- `/`* `/`+ ` for unordered, `N. ` for ordered — marker kept verbatim
    /// (real number, not renumbered) so the rendered list matches the source.
    private static func listItemMatch(_ line: String) -> (String, String)? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return ("•", String(line.dropFirst(2)))
        }
        guard let dotIndex = line.firstIndex(of: "."), line.index(after: dotIndex) < line.endIndex,
              line[line.index(after: dotIndex)] == " " else { return nil }
        let prefix = line[..<dotIndex]
        guard !prefix.isEmpty, prefix.allSatisfy({ $0.isNumber }) else { return nil }
        let text = line[line.index(dotIndex, offsetBy: 2)...]
        return ("\(prefix).", String(text))
    }
}
