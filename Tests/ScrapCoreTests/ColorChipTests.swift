import XCTest
@testable import ScrapCore

final class ColorChipTests: XCTestCase {
    private func chips(_ text: String) -> [(String, UInt32)] {
        let ns = text as NSString
        return MarkdownHighlighter.spans(in: text).compactMap { span in span.chip.map { (ns.substring(with: span.range), $0) } }
    }

    func testLongCodesAreChipsAnywhere() {
        let found = chips("brand blue #0352BF and #ff000080 here")
        XCTAssertEqual(found.map(\.0), ["#0352BF", "#ff000080"])
        XCTAssertEqual(found.map(\.1), [0x0352BFFF, 0xFF000080])
    }

    func testShortCodesOnlyInsideBackticks() {
        XCTAssertEqual(chips("issue #123 and #abc and #fffa").count, 0, "bare short codes are usually not colours")
        let found = chips("use `#0af` or `color: #f008;`")
        XCTAssertEqual(found.map(\.0), ["#0af", "#f008"])
        XCTAssertEqual(found.map(\.1), [0x00AAFFFF, 0xFF000088])
    }

    func testNotHeadingsNotWordsNotLinks() {
        XCTAssertEqual(chips("# Heading").count, 0)
        XCTAssertEqual(chips("## 0352BF").count, 0)
        XCTAssertEqual(chips("see page#abc123 or https://x.com/#0352BF and [x](https://x.com/#0352BF)").count, 0)
        XCTAssertEqual(chips("#0352BFX and #0352BF1 and a#0352BF and &#0352BF;").count, 0, "must stand alone")
        XCTAssertEqual(chips("#12345 and #1234567").count, 0, "wrong lengths")
    }

    func testPunctuationAroundACodeIsFine() {
        XCTAssertEqual(chips("(#0352BF), #0352BF. \"#0352BF\" #0352BF!").count, 4)
    }

    func testCodeBlocksAreLeftAlone() {
        XCTAssertEqual(chips("```css\ncolor: #0352BF;\n```").count, 0)
    }

    func testColorValues() {
        XCTAssertEqual(MarkdownHighlighter.colorValue("fff"), 0xFFFFFFFF)
        XCTAssertEqual(MarkdownHighlighter.colorValue("0352bf"), 0x0352BFFF)
        XCTAssertNil(MarkdownHighlighter.colorValue("12345"))
        XCTAssertNil(MarkdownHighlighter.colorValue("gggggg"))
    }
}
