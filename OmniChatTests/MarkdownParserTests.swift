import XCTest
@testable import OmniChat

final class MarkdownParserTests: XCTestCase {
    func test_parse_plainParagraph_returnsSingleParagraphBlock() {
        let blocks = MarkdownParser.parse("Bonjour, comment puis-je vous aider ?")
        XCTAssertEqual(blocks, [.paragraph(text: "Bonjour, comment puis-je vous aider ?")])
    }

    func test_parse_heading_returnsHeadingBlockWithLevel() {
        let blocks = MarkdownParser.parse("### Les piliers du bonheur")
        XCTAssertEqual(blocks, [.heading(level: 3, text: "Les piliers du bonheur")])
    }

    func test_parse_hashWithoutSpace_isNotTreatedAsHeading() {
        let blocks = MarkdownParser.parse("#nofollow is a tag")
        XCTAssertEqual(blocks, [.paragraph(text: "#nofollow is a tag")])
    }

    func test_parse_horizontalRule_returnsRuleBlock() {
        let blocks = MarkdownParser.parse("Avant\n\n---\n\nAprès")
        XCTAssertEqual(blocks, [.paragraph(text: "Avant"), .rule, .paragraph(text: "Après")])
    }

    func test_parse_unorderedListItems_returnBulletMarker() {
        let blocks = MarkdownParser.parse("- Premier point\n- Deuxième point")
        XCTAssertEqual(blocks, [
            .listItem(marker: "•", text: "Premier point"),
            .listItem(marker: "•", text: "Deuxième point"),
        ])
    }

    func test_parse_orderedListItems_preserveRealNumber() {
        let blocks = MarkdownParser.parse("1. Un\n2. Deux")
        XCTAssertEqual(blocks, [
            .listItem(marker: "1.", text: "Un"),
            .listItem(marker: "2.", text: "Deux"),
        ])
    }

    func test_parse_fencedCodeBlock_capturesRawTextWithoutFences() {
        let blocks = MarkdownParser.parse("```swift\nlet x = 1\n```")
        XCTAssertEqual(blocks, [.codeBlock(text: "let x = 1")])
    }

    func test_parse_unterminatedCodeFence_stillCapturesContent() {
        let blocks = MarkdownParser.parse("```\nlet x = 1")
        XCTAssertEqual(blocks, [.codeBlock(text: "let x = 1")])
    }

    func test_parse_multipleParagraphs_separatedByBlankLine() {
        let blocks = MarkdownParser.parse("Premier paragraphe.\n\nDeuxième paragraphe.")
        XCTAssertEqual(blocks, [
            .paragraph(text: "Premier paragraphe."),
            .paragraph(text: "Deuxième paragraphe."),
        ])
    }

    func test_parse_mixedContent_producesOrderedBlockSequence() {
        let content = "### Titre\n\nUn paragraphe.\n\n- item un\n- item deux\n\n---\n\nDernier mot."
        let blocks = MarkdownParser.parse(content)
        XCTAssertEqual(blocks, [
            .heading(level: 3, text: "Titre"),
            .paragraph(text: "Un paragraphe."),
            .listItem(marker: "•", text: "item un"),
            .listItem(marker: "•", text: "item deux"),
            .rule,
            .paragraph(text: "Dernier mot."),
        ])
    }

    func test_parse_emptyString_returnsNoBlocks() {
        XCTAssertEqual(MarkdownParser.parse(""), [])
    }
}
