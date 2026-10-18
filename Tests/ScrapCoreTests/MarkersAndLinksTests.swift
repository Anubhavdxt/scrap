import XCTest
@testable import ScrapCore

final class MarkersAndLinksTests: XCTestCase {
    private func spans(_ text: String) -> [Span] { MarkdownHighlighter.spans(in: text) }
    private func text(_ s: Span, in source: String) -> String { (source as NSString).substring(with: s.range) }

    private func marker(_ source: String) -> (String, ListMarker)? {
        spans(source).first { $0.marker != nil }.map { (text($0, in: source), $0.marker!) }
    }

    private func urls(_ source: String) -> [(String, String)] {
        spans(source).compactMap { span in span.url.map { (text(span, in: source), $0) } }
    }

    // MARK: List markers

    func testBulletTaskAndNumberMarkers() {
        XCTAssertEqual(marker("- item")?.0, "- ")
        XCTAssertEqual(marker("- item")?.1, ListMarker(kind: .bullet, indentColumns: 0, columns: 2))
        XCTAssertEqual(marker("* item")?.1.kind, .bullet)
        XCTAssertEqual(marker("+ item")?.1.kind, .bullet)
        XCTAssertEqual(marker("- [ ] todo")?.0, "- [ ] ")
        XCTAssertEqual(marker("- [ ] todo")?.1, ListMarker(kind: .taskOpen, indentColumns: 0, columns: 6))
        XCTAssertEqual(marker("- [x] done")?.1.kind, .taskDone)
        XCTAssertEqual(marker("- [X] done")?.1.kind, .taskDone)
        XCTAssertEqual(marker("12. step")?.0, "12. ")
        XCTAssertEqual(marker("12. step")?.1.kind, .number)
        XCTAssertEqual(marker("1) step")?.1.kind, .number)
    }

    func testIndentationIsMeasuredInCells() {
        XCTAssertEqual(marker("    - nested")?.1.indentColumns, 4)
        XCTAssertEqual(marker("\t- tabbed")?.1.indentColumns, 4)
        XCTAssertEqual(marker("  - [ ] t")?.0, "- [ ] ", "the marker region starts after the indentation")
    }

    func testNoMarkerOnPlainTextHeadingsOrCode() {
        for text in ["plain", "-nope", "1.nope", "# - not a list", "```\n- item\n```"] {
            XCTAssertNil(marker(text), text)
        }
    }

    func testFinishedTasksAreStruckThrough() {
        let source = "- [x] write tests"
        let struck = spans(source).first { $0.strike }
        XCTAssertEqual(struck.map { text($0, in: source) }, "write tests")
        XCTAssertNil(spans("- [ ] open").first { $0.strike })
        XCTAssertNil(spans("- plain").first { $0.strike })
    }

    // MARK: Links

    func testBareURLsBecomeLinks() {
        XCTAssertEqual(urls("see https://example.com/a?b=1 now").map(\.1), ["https://example.com/a?b=1"])
        XCTAssertEqual(urls("see https://example.com/a?b=1 now").map(\.0), ["https://example.com/a?b=1"])
        XCTAssertEqual(urls("go to www.example.com today").map(\.1), ["https://www.example.com"])
        XCTAssertEqual(urls("mail mailto:me@example.com please").map(\.1), ["mailto:me@example.com"])
    }

    func testTrailingPunctuationIsNotPartOfTheLink() {
        XCTAssertEqual(urls("Read https://example.com/x.").map(\.0), ["https://example.com/x"])
        XCTAssertEqual(urls("(see https://example.com/x), ok").map(\.0), ["https://example.com/x"])
        XCTAssertEqual(urls("https://en.wikipedia.org/wiki/Swift_(language)").map(\.0), ["https://en.wikipedia.org/wiki/Swift_(language)"], "balanced parentheses stay")
        XCTAssertEqual(urls("is it https://example.com?").map(\.0), ["https://example.com"])
    }

    func testMarkdownLinksCarryTheirURLOnTheText() {
        let source = "a [the docs](https://example.com/docs) b"
        XCTAssertEqual(urls(source).map(\.0), ["the docs"])
        XCTAssertEqual(urls(source).map(\.1), ["https://example.com/docs"])
        XCTAssertEqual(urls("[home](www.example.com)").map(\.1), ["https://www.example.com"])
    }

    func testAngleBracketAutolinksAndImages() {
        XCTAssertEqual(urls("<https://example.com/a>").map(\.0), ["https://example.com/a"])
        XCTAssertEqual(urls("![alt](https://example.com/i.png)").count, 0, "images aren't links")
    }

    func testLinksInHeadingsQuotesAndListsWork() {
        XCTAssertEqual(urls("# Title https://example.com").count, 1)
        XCTAssertEqual(urls("> quoted https://example.com").count, 1)
        XCTAssertEqual(urls("- item https://example.com").count, 1)
        XCTAssertEqual(urls("- [ ] task https://example.com").count, 1)
    }

    func testNoLinksInCode() {
        XCTAssertEqual(urls("`https://example.com`").count, 0)
        XCTAssertEqual(urls("```\nhttps://example.com\n```").count, 0)
    }

    func testTwoLinksOnOneLine() {
        XCTAssertEqual(urls("https://a.com and https://b.com").map(\.1), ["https://a.com", "https://b.com"])
    }

    // MARK: Backspace

    private func backspace(_ text: String, _ at: Int) -> (String, Int)? {
        guard let e = ListEditing.backspace(in: text, selection: NSRange(location: at, length: 0)) else { return nil }
        return ((text as NSString).replacingCharacters(in: e.range, with: e.replacement), e.selection.location)
    }

    func testBackspaceAfterATaskMarkerLeavesAPlainBullet() {
        XCTAssertEqual(backspace("- [ ] buy", 6)?.0, "- buy")
        XCTAssertEqual(backspace("- [ ] buy", 6)?.1, 2)
        XCTAssertEqual(backspace("- [x] buy", 6)?.0, "- buy")
        let again = backspace("- buy", 2)
        XCTAssertEqual(again?.0, "buy")
        XCTAssertEqual(again?.1, 0)
    }

    func testBackspaceKeepsIndentationAndLeavesNumbersAlone() {
        XCTAssertEqual(backspace("  - item", 4)?.0, "  item")
        XCTAssertNil(backspace("1. item", 3), "numbers delete one character at a time")
        XCTAssertNil(backspace("- item", 4), "only right after the marker")
        XCTAssertNil(backspace("plain", 3))
        XCTAssertEqual(backspace("a\n- [ ] ", 8)?.0, "a\n- ", "an empty task item")
    }
}
