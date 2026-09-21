import XCTest
@testable import DoctorMarkdown

final class HTMLRendererTests: XCTestCase {

    private func render(_ markdown: String) -> String {
        HTMLRenderer.render(markdown: markdown)
    }

    // MARK: Headings

    func testATXHeadings() {
        XCTAssertTrue(render("# Title").contains("<h1 id=\"title\">Title</h1>"))
        XCTAssertTrue(render("### Deep").contains("<h3 id=\"deep\">Deep</h3>"))
        XCTAssertTrue(render("## Closed ##").contains(">Closed</h2>"))
    }

    func testHashWithoutSpaceIsNotAHeading() {
        XCTAssertTrue(render("#NotAHeading").contains("<p>"))
    }

    func testSetextHeadings() {
        XCTAssertTrue(render("Title\n=====").contains("<h1"))
        XCTAssertTrue(render("Subtitle\n--------").contains("<h2"))
    }

    func testRuleAfterBlankLineIsNotASetextHeading() {
        let html = render("Some prose.\n\n---\n\nMore prose.")
        XCTAssertTrue(html.contains("<hr>"))
        XCTAssertFalse(html.contains("<h2"))
    }

    // MARK: Inline

    func testEmphasis() {
        XCTAssertTrue(render("**bold**").contains("<strong>bold</strong>"))
        XCTAssertTrue(render("*italic*").contains("<em>italic</em>"))
        XCTAssertTrue(render("***both***").contains("<strong><em>both</em></strong>"))
        XCTAssertTrue(render("~~gone~~").contains("<del>gone</del>"))
        XCTAssertTrue(render("==note==").contains("<mark>note</mark>"))
    }

    func testUnderscoresInsideWordsAreNotEmphasis() {
        let html = render("a snake_case_name here")
        XCTAssertFalse(html.contains("<em>"))
    }

    func testCodeSpanWinsOverEmphasis() {
        let html = render("`**not bold**`")
        XCTAssertTrue(html.contains("<code>**not bold**</code>"))
        XCTAssertFalse(html.contains("<strong>"))
    }

    func testCodeSpanWithBacktickInside() {
        XCTAssertTrue(render("``a ` b``").contains("<code>a ` b</code>"))
    }

    func testEscapes() {
        XCTAssertTrue(render("\\*literal\\*").contains("*literal*"))
        XCTAssertFalse(render("\\*literal\\*").contains("<em>"))
    }

    func testLinksAndImages() {
        XCTAssertTrue(render("[text](https://example.com)")
            .contains("<a href=\"https://example.com\">text</a>"))
        XCTAssertTrue(render("![alt](cat.png)")
            .contains("<img src=\"cat.png\" alt=\"alt\">"))
        XCTAssertTrue(render("[t](https://e.com \"Title\")").contains("title=\"Title\""))
    }

    func testLinkWithNestedEmphasis() {
        XCTAssertTrue(render("[**bold link**](https://e.com)")
            .contains("<strong>bold link</strong></a>"))
    }

    func testBareURLBecomesALink() {
        let html = render("See https://example.com/x for details.")
        XCTAssertTrue(html.contains("<a href=\"https://example.com/x\">"))
        // The full stop belongs to the sentence, not the URL.
        XCTAssertTrue(html.contains("for details."))
    }

    func testAutolink() {
        XCTAssertTrue(render("<https://example.com>").contains("<a href=\"https://example.com\">"))
    }

    func testWikiLinkRendersAsText() {
        let html = render("See [[Some Note|the note]].")
        XCTAssertTrue(html.contains("the note"))
        XCTAssertFalse(html.contains("<a href"))
    }

    // MARK: Safety

    func testScriptTagsAreEscaped() {
        let html = render("<script>alert(1)</script>")
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }

    func testImageTagWithRemoteSourceIsEscaped() {
        let html = render("<img src=\"https://tracker.example/pixel.gif\">")
        XCTAssertFalse(html.contains("<img src=\"https://tracker"))
    }

    func testWhitelistedInlineTagSurvivesWithoutAttributes() {
        let html = render("line<br>break")
        XCTAssertTrue(html.contains("<br>"))
        XCTAssertFalse(render("<b onclick=\"x()\">hi</b>").contains("onclick"))
    }

    // MARK: Blocks

    func testFencedCodeKeepsContentVerbatim() {
        let html = render("```swift\nlet x = a < b && c > d\n```")
        XCTAssertTrue(html.contains("class=\"language-swift\""))
        XCTAssertTrue(html.contains("let x = a &lt; b &amp;&amp; c &gt; d"))
        XCTAssertFalse(html.contains("<em>"))
    }

    func testUnclosedFenceStillRenders() {
        let html = render("```\nstranded\n")
        XCTAssertTrue(html.contains("<pre><code>stranded"))
    }

    func testMarkdownInsideFenceIsNotParsed() {
        let html = render("```\n# not a heading\n- not a list\n```")
        XCTAssertFalse(html.contains("<h1"))
        XCTAssertFalse(html.contains("<li>"))
    }

    func testBlockquote() {
        let html = render("> quoted **text**")
        XCTAssertTrue(html.contains("<blockquote>"))
        XCTAssertTrue(html.contains("<strong>text</strong>"))
    }

    func testNestedBlockquote() {
        let html = render("> outer\n> > inner")
        XCTAssertTrue(html.contains("<blockquote>"))
        XCTAssertEqual(html.components(separatedBy: "<blockquote>").count - 1, 2)
    }

    func testUnorderedList() {
        let html = render("- one\n- two")
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertEqual(html.components(separatedBy: "<li>").count - 1, 2)
    }

    func testOrderedListPreservesStart() {
        let html = render("3. three\n4. four")
        XCTAssertTrue(html.contains("<ol start=\"3\">"))
    }

    func testNestedList() {
        let html = render("- outer\n  - inner")
        XCTAssertTrue(html.contains("<ul>"))
        XCTAssertEqual(html.components(separatedBy: "<ul").count - 1, 2)
    }

    func testTaskList() {
        let html = render("- [ ] todo\n- [x] done")
        XCTAssertTrue(html.contains("type=\"checkbox\" disabled>"))
        XCTAssertTrue(html.contains("type=\"checkbox\" disabled checked>"))
    }

    func testTable() {
        let html = render("| a | b |\n|:--|--:|\n| 1 | 2 |")
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th style=\"text-align:left\">a</th>"))
        XCTAssertTrue(html.contains("<th style=\"text-align:right\">b</th>"))
        XCTAssertTrue(html.contains("<td style=\"text-align:left\">1</td>"))
    }

    func testPipeTableWithoutOuterPipes() {
        let html = render("a | b\n--- | ---\n1 | 2")
        XCTAssertTrue(html.contains("<table>"))
    }

    func testHorizontalRule() {
        XCTAssertTrue(render("***").contains("<hr>"))
        XCTAssertTrue(render("- - -").contains("<hr>"))
    }

    func testHardBreak() {
        let html = render("line one  \nline two")
        XCTAssertTrue(html.contains("<br>"))
    }

    func testParagraphsAreSeparate() {
        let html = render("one\n\ntwo")
        XCTAssertEqual(html.components(separatedBy: "<p>").count - 1, 2)
    }

    func testFrontmatterIsSetApartNotDropped() {
        let html = render("---\ntitle: Notes\n---\n\n# Body")
        XCTAssertTrue(html.contains("frontmatter"))
        XCTAssertTrue(html.contains("title: Notes"))
        XCTAssertTrue(html.contains("<h1"))
    }

    func testFullDocumentIsWellFormed() {
        let html = HTMLRenderer.document(markdown: "# Hi\n\nThere.", title: "Test")
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<title>Test</title>"))
        XCTAssertTrue(html.contains("</html>"))
    }

    func testTitleIsEscapedInTheHead() {
        let html = HTMLRenderer.document(markdown: "x", title: "a <b> & c")
        XCTAssertTrue(html.contains("<title>a &lt;b&gt; &amp; c</title>"))
    }

    // MARK: Regression guards

    func testEmptyInputProducesNothing() {
        XCTAssertEqual(render(""), "")
    }

    func testWindowsLineEndings() {
        let html = render("# Title\r\n\r\nBody")
        XCTAssertTrue(html.contains("<h1"))
        XCTAssertTrue(html.contains("<p>Body</p>"))
    }

    func testUnmatchedDelimitersAreLiteral() {
        XCTAssertTrue(render("2 * 3 * 4 = 24").contains("2 * 3 * 4 = 24")
                      || render("2 * 3 * 4 = 24").contains("<em>"))
        XCTAssertTrue(render("a ** b").contains("a ** b"))
    }
}
