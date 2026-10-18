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

/// Bold and italic together, in every spelling people (and the ⌘B/⌘I shortcuts) produce.
final class NestedEmphasisTests: XCTestCase {
    private func styled(_ source: String) -> [(text: String, bold: Bool, italic: Bool)] {
        let ns = source as NSString
        return MarkdownHighlighter.spans(in: source).filter { !$0.syntax && ($0.bold || $0.italic) }
            .map { (ns.substring(with: $0.range), $0.bold, $0.italic) }
    }

    private func syntax(_ source: String) -> [String] {
        let ns = source as NSString
        return MarkdownHighlighter.spans(in: source).filter(\.syntax).map { ns.substring(with: $0.range) }
    }

    func testTripleMarkersAreBoldAndItalicInOneSpan() {
        for source in ["***both***", "___both___"] {
            let spans = styled(source)
            XCTAssertEqual(spans.count, 1, source)
            XCTAssertEqual(spans.first?.text, source)
            XCTAssertEqual(spans.first?.bold, true)
            XCTAssertEqual(spans.first?.italic, true)
            XCTAssertEqual(syntax(source).count, 2, "three marker characters at each end")
            XCTAssertEqual(syntax(source).map(\.count), [3, 3])
        }
    }

    func testItalicInsideBold() {
        let spans = styled("**bold *both* bold**")
        XCTAssertTrue(spans.contains { $0.text == "**bold *both* bold**" && $0.bold })
        XCTAssertTrue(spans.contains { $0.text == "*both*" && $0.italic })
        XCTAssertEqual(syntax("**bold *both* bold**").map(\.count).sorted(), [1, 1, 2, 2])
    }

    func testBoldInsideItalic() {
        let spans = styled("*it **both** it*")
        XCTAssertTrue(spans.contains { $0.text == "*it **both** it*" && $0.italic })
        XCTAssertTrue(spans.contains { $0.text == "**both**" && $0.bold })
    }

    func testMixedMarkerStyles() {
        for (source, outer, inner) in [("_**x**_", "_**x**_", "**x**"), ("**_x_**", "**_x_**", "_x_"), ("*__x__*", "*__x__*", "__x__")] {
            let spans = styled(source)
            XCTAssertTrue(spans.contains { $0.text == outer }, source)
            XCTAssertTrue(spans.contains { $0.text == inner }, source)
            XCTAssertTrue(spans.contains { $0.bold }, source)
            XCTAssertTrue(spans.contains { $0.italic }, source)
        }
    }

    func testSeparateWordsStaySeparate() {
        let spans = styled("**one** and *two* and ***three***")
        XCTAssertEqual(spans.count, 3)
        XCTAssertEqual(spans.filter { $0.bold && !$0.italic }.map(\.text), ["**one**"])
        XCTAssertEqual(spans.filter { $0.italic && !$0.bold }.map(\.text), ["*two*"])
        XCTAssertEqual(spans.filter { $0.bold && $0.italic }.map(\.text), ["***three***"])
    }

    func testPlainTextAndSnakeCaseAreNotEmphasis() {
        XCTAssertTrue(styled("snake_case_name and my_var_name and a * b and 5 * 6").isEmpty)
        XCTAssertFalse(styled("2*3*4").isEmpty, "asterisks may be intraword, as in CommonMark")
        XCTAssertTrue(styled("__init__ is bold in markdown").contains { $0.bold }, "unchanged: double underscores are bold")
    }

    func testCodeAndLinksStayAsTheyWere() {
        XCTAssertTrue(styled("`**not bold**`").isEmpty)
        XCTAssertTrue(styled("[***x***](https://a.b)").isEmpty, "inside a link's own brackets nothing nests")
    }

    func testTheFormattingShortcutsProduceWhatTheStylerUnderstands() {
        // ⌘B then ⌘I on a word gives `***word***`, which must read as bold and italic.
        var text = "make word loud"
        var selection = NSRange(location: 5, length: 4)
        for style in [Formatting.Style.bold, .italic] {
            let edit = Formatting.toggle(style, in: text, selection: selection)!
            text = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
            selection = edit.selection
        }
        XCTAssertEqual(text, "make ***word*** loud")
        let both = styled(text)
        XCTAssertEqual(both.count, 1)
        XCTAssertTrue(both[0].bold && both[0].italic)
    }
}
