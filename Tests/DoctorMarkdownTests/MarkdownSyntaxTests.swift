import XCTest
@testable import DoctorMarkdown

/// The scanner drives what the editor draws, and its ranges index straight into
/// an `NSTextStorage`. An off-by-one here shows up as attributes landing on the
/// wrong characters, so the range arithmetic is worth pinning down.
final class MarkdownSyntaxTests: XCTestCase {

    private func scan(_ text: String) -> [LineToken] {
        MarkdownSyntax.scan(text as NSString)
    }

    // MARK: Line enumeration

    func testLineRangesWithoutTrailingNewline() {
        let ranges = MarkdownSyntax.lineRanges(in: "abc" as NSString)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].location, 0)
        XCTAssertEqual(ranges[0].length, 3)
    }

    func testLineRangesWithTrailingNewline() {
        let ranges = MarkdownSyntax.lineRanges(in: "abc\n" as NSString)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges[1].length, 0)
    }

    func testLineRangesOfEmptyString() {
        let ranges = MarkdownSyntax.lineRanges(in: "" as NSString)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].length, 0)
    }

    func testLineRangesCoverEveryCharacterExactlyOnce() {
        let text = "# One\n\nTwo three\n- four\n"
        let ranges = MarkdownSyntax.lineRanges(in: text as NSString)
        let covered = ranges.reduce(0) { $0 + $1.length }
        // Every character except the newlines belongs to exactly one line.
        let newlines = text.filter { $0 == "\n" }.count
        XCTAssertEqual(covered, (text as NSString).length - newlines)
    }

    // MARK: Classification

    func testHeadingClassification() {
        let tokens = scan("## Heading")
        XCTAssertEqual(tokens.first?.kind, .heading(level: 2))
        // "## " is punctuation; "Heading" is the text.
        XCTAssertEqual(tokens.first?.markers.first?.length, 3)
        XCTAssertEqual(tokens.first?.content.location, 3)
    }

    func testBulletAndTaskClassification() {
        XCTAssertEqual(scan("- item").first?.kind, .bullet)
        XCTAssertEqual(scan("1. item").first?.kind, .ordered)
        XCTAssertEqual(scan("- [ ] item").first?.kind, .task(checked: false))
        XCTAssertEqual(scan("- [x] item").first?.kind, .task(checked: true))
    }

    func testBulletNeedsASpace() {
        XCTAssertEqual(scan("-not-a-list").first?.kind, .paragraph)
    }

    func testFenceStateSuppressesMarkdownInside() {
        let tokens = scan("```\n# not a heading\n```")
        XCTAssertEqual(tokens[1].kind, .codeLine)
        XCTAssertEqual(tokens[2].kind, .fenceClose)
    }

    func testFenceLanguageIsContentNotPunctuation() {
        let tokens = scan("```swift\nx\n```")
        XCTAssertEqual(tokens[0].kind, .fenceOpen(language: "swift"))
        // The backticks are hidden; "swift" is kept as a visible label.
        XCTAssertEqual(tokens[0].markers.last?.length, 3)
        XCTAssertEqual(tokens[0].content.length, 5)
    }

    func testBlockquoteDepth() {
        XCTAssertEqual(scan("> one").first?.quoteDepth, 1)
        XCTAssertEqual(scan("> > two").first?.quoteDepth, 2)
    }

    func testQuotedListKeepsBothMarkers() {
        let token = scan("> - item").first
        XCTAssertEqual(token?.quoteDepth, 1)
        XCTAssertEqual(token?.kind, .bullet)
        XCTAssertEqual(token?.markers.count, 2)
    }

    func testFrontmatterOnlyCountsAtTheTop() {
        XCTAssertEqual(scan("---\nkey: v\n---\n").first?.kind, .frontmatterFence)
        XCTAssertEqual(scan("text\n\n---\n")[2].kind, .horizontalRule)
    }

    func testTableNeedsADelimiterRow() {
        XCTAssertEqual(scan("| a | b |\n|---|---|\n| 1 | 2 |")[1].kind, .tableDelimiter)
        XCTAssertEqual(scan("a | b").first?.kind, .paragraph)
    }

    func testIndentedCodeOnlyAfterABlankLine() {
        XCTAssertEqual(scan("\n    code").last?.kind, .indentedCode)
        XCTAssertEqual(scan("text\n    continued").last?.kind, .paragraph)
    }

    // MARK: Ranges with non-ASCII text

    func testRangesAreUTF16CorrectWithEmoji() {
        let text = "# 🎉 Party"
        let token = scan(text).first
        // "# " is two UTF-16 units regardless of what follows it.
        XCTAssertEqual(token?.markers.first?.length, 2)
        XCTAssertEqual(token?.content.location, 2)
        XCTAssertEqual(NSMaxRange(token!.content), (text as NSString).length)
    }

    func testSecondLineRangesAccountForEmojiOnTheFirst() {
        let text = "🎉\n## Two"
        let tokens = scan(text)
        XCTAssertEqual(tokens.count, 2)
        let expected = ("🎉\n" as NSString).length
        XCTAssertEqual(tokens[1].range.location, expected)
        XCTAssertEqual(tokens[1].markers.first?.location, expected)
    }

    // MARK: Inline spans

    private func spans(_ text: String) -> [InlineToken] {
        let ns = text as NSString
        return MarkdownSyntax.inlineTokens(in: ns, range: NSRange(location: 0, length: ns.length))
    }

    func testInlineStrongAndEmphasis() {
        XCTAssertEqual(spans("**bold**").first?.kind, .strong)
        XCTAssertEqual(spans("*thin*").first?.kind, .emphasis)
    }

    func testCodeSpanClaimsItsContents() {
        let found = spans("`**x**`")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.kind, .code)
    }

    func testLinkExposesItsDestination() {
        let text = "[label](https://example.com)"
        let found = spans(text)
        guard let link = found.first, let destination = link.destination else {
            return XCTFail("no link found")
        }
        XCTAssertEqual(link.kind, .link)
        XCTAssertEqual((text as NSString).substring(with: link.content), "label")
        XCTAssertEqual((text as NSString).substring(with: destination), "https://example.com")
    }

    func testSpansAreSortedAndDoNotOverlap() {
        let found = spans("*a* and **b** and `c`")
        XCTAssertEqual(found.count, 3)
        for (previous, next) in zip(found, found.dropFirst()) {
            XCTAssertLessThanOrEqual(NSMaxRange(previous.range), next.range.location)
        }
    }

    func testTableRowSplitting() {
        XCTAssertEqual(MarkdownSyntax.splitTableRow("| a | b |"), [" a ", " b "])
        XCTAssertEqual(MarkdownSyntax.splitTableRow("a | b"), ["a ", " b"])
        // An escaped pipe stays inside its cell.
        XCTAssertEqual(MarkdownSyntax.splitTableRow("| a \\| b |").count, 1)
    }

    func testTableDelimiterDetection() {
        XCTAssertTrue(MarkdownSyntax.isTableDelimiter("|---|---|"))
        XCTAssertTrue(MarkdownSyntax.isTableDelimiter("|:--|--:|"))
        XCTAssertFalse(MarkdownSyntax.isTableDelimiter("| a | b |"))
    }

    // MARK: Volume

    func testLargeDocumentScansInReasonableTime() {
        let paragraph = "## Section\n\nSome **prose** with a [link](https://example.com) and `code`.\n\n"
        let document = String(repeating: paragraph, count: 2_000) as NSString
        let started = Date()
        let tokens = MarkdownSyntax.scan(document)
        XCTAssertGreaterThan(tokens.count, 5_000)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2.0)
    }
}

extension MarkdownSyntaxTests {
    func testSetextUnderlinePromotesTheLineAbove() {
        let tokens = MarkdownSyntax.scan("Title\n=====" as NSString)
        XCTAssertEqual(tokens[0].kind, .heading(level: 1))
        XCTAssertEqual(tokens[1].kind, .setextUnderline(level: 1))
    }

    func testDashUnderlineAfterAParagraphIsAHeadingNotARule() {
        let tokens = MarkdownSyntax.scan("Title\n---" as NSString)
        XCTAssertEqual(tokens[0].kind, .heading(level: 2))
        XCTAssertEqual(tokens[1].kind, .setextUnderline(level: 2))
    }
}
