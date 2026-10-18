import XCTest
@testable import ScrapCore

/// The structure the editor draws live: syntax characters to dim or hide, heading levels, panels, quotes.
final class LiveMarkdownTests: XCTestCase {
    private func spans(_ text: String) -> [Span] { MarkdownHighlighter.spans(in: text) }
    private func text(_ s: Span, _ source: String) -> String { (source as NSString).substring(with: s.range) }
    private func syntax(_ source: String) -> [String] { spans(source).filter(\.syntax).map { text($0, source) } }

    func testEmphasisMarkersAreSyntax() {
        XCTAssertEqual(syntax("a **b** c"), ["**", "**"])
        XCTAssertEqual(syntax("a *b* c"), ["*", "*"])
        XCTAssertEqual(syntax("a _b_ c"), ["_", "_"])
        XCTAssertEqual(syntax("a ~~b~~ c"), ["~~", "~~"])
        XCTAssertEqual(syntax("a `b` c"), ["`", "`"])
        XCTAssertEqual(syntax("a ``b ` c`` d"), ["``", "``"], "longer backtick runs")
    }

    func testStrikethroughIsStruckAndDimmed() {
        let source = "x ~~gone~~ y"
        let struck = spans(source).first { $0.strike }
        XCTAssertEqual(struck.map { text($0, source) }, "~~gone~~")
        XCTAssertNil(spans("~~ not~~").first { $0.strike }, "needs non-space next to the markers, like bold")
    }

    func testInlineCodeIsFlagged() {
        let source = "run `make app` now"
        XCTAssertEqual(spans(source).first { $0.inlineCode }.map { text($0, source) }, "`make app`")
    }

    func testHeadingLevelsAndTheirMarker() {
        for (source, level, marker) in [("# One", 1, "# "), ("### Three", 3, "### "), ("###### Six", 6, "###### ")] {
            XCTAssertEqual(spans(source).first { $0.heading > 0 }?.heading, level, source)
            XCTAssertEqual(syntax(source), [marker], source)
        }
        XCTAssertTrue(spans("#hashtag").allSatisfy { $0.heading == 0 }, "needs a space after the #")
    }

    func testBoldInsideAHeadingIsLeftToTheHeading() {
        XCTAssertEqual(syntax("# a **b** c"), ["# "], "headings are already bold, so emphasis inside isn't parsed")
    }

    func testQuoteMarkerAndFlag() {
        XCTAssertEqual(syntax("> quoted"), ["> "])
        XCTAssertEqual(syntax(">tight"), [">"])
        XCTAssertTrue(spans("> q").contains { $0.quote })
        XCTAssertFalse(spans("not > a quote").contains { $0.quote })
    }

    func testLinkBracketsAreSyntaxButBareURLsAreNot() {
        XCTAssertEqual(syntax("see [docs](https://x.y/z) ok"), ["[", "](https://x.y/z)"])
        XCTAssertEqual(syntax("see https://x.y/z ok"), [])
        XCTAssertEqual(syntax("![alt](https://x.y/i.png)"), [], "images keep their text")
    }

    func testFencedBlocksMarkEveryLineIncludingTheFences() {
        let source = "before\n```swift\nlet a = 1\n\nlet b = 2\n```\nafter"
        let blockLines = spans(source).filter(\.block).map { text($0, source) }
        XCTAssertEqual(blockLines, ["```swift", "let a = 1", "", "let b = 2", "```"], "blank lines inside the block are included")
        let fences = spans(source).filter { $0.block && $0.syntax }.map { text($0, source) }
        XCTAssertEqual(fences, ["```swift", "```"])
        XCTAssertFalse(spans(source).contains { $0.block && text($0, source).contains("before") })
    }

    func testCodeLexerSpansAreMarkedAsCode() {
        let source = "```swift\nlet a = 1\n```"
        let keyword = spans(source).first { text($0, source) == "let" }
        XCTAssertEqual(keyword?.code, true)
        XCTAssertEqual(keyword?.token, .keyword)
        XCTAssertTrue(spans("**b**").allSatisfy { !$0.code })
    }

    func testNothingElseGetsSyntaxInsideCode() {
        XCTAssertEqual(syntax("```\n**not bold** # not heading\n```"), ["```", "```"])
    }

    func testStyledTextOnAListLineKeepsItsMarkers() {
        let source = "- [ ] do **this** now"
        XCTAssertEqual(syntax(source), ["**", "**"])
        XCTAssertNotNil(spans(source).first { $0.marker?.kind == .taskOpen })
    }
}
