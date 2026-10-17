import XCTest
@testable import ScrapCore

final class HighlighterTests: XCTestCase {
    private func tokens(_ text: String) -> [(String, Token)] {
        let ns = text as NSString
        return MarkdownHighlighter.spans(in: text).map { (ns.substring(with: $0.range), $0.token) }
    }

    func testHeadingBoldCodeAndLink() {
        let t = tokens("# Title\nsome **bold** and `code` and [x](http://a.b)")
        XCTAssertTrue(t.contains { $0 == ("# Title", .title) })
        XCTAssertTrue(t.contains { $0 == ("**bold**", .keyword) })
        XCTAssertTrue(t.contains { $0 == ("`code`", .string) })
        XCTAssertTrue(t.contains { $0 == ("x", .attr) })
    }

    func testBulletAndQuote() {
        let t = tokens("- item\n> quoted")
        XCTAssertTrue(t.contains { $0 == ("-", .number) })
        XCTAssertTrue(t.contains { $0 == ("> quoted", .comment) })
    }

    func testFencedCode() {
        let t = tokens("```swift\nfunc go() { return \"hi\" } // done\n```\nafter **b**")
        XCTAssertTrue(t.contains { $0 == ("func", .keyword) })
        XCTAssertTrue(t.contains { $0 == ("go", .title) })
        XCTAssertTrue(t.contains { $0 == ("\"hi\"", .string) })
        XCTAssertTrue(t.contains { $0 == ("// done", .comment) })
        XCTAssertTrue(t.contains { $0 == ("**b**", .keyword) }, "markdown resumes after the fence closes")
    }

    func testNothingStyledInsideCodeSpan() {
        let t = tokens("`**not bold**`")
        XCTAssertEqual(t.count, 1)
    }

    func testBlockCommentSpansLines() {
        let t = tokens("```c\n/* a\nb */ int\n```")
        XCTAssertTrue(t.contains { $0 == ("b */", .comment) })
    }

    func testThemes() {
        XCTAssertEqual(Themes.all.count, 18)
        XCTAssertEqual(Themes.families.count, 9)
        XCTAssertEqual(Themes.theme(family: "dracula", dark: true).id, "dracula-dark")
        XCTAssertEqual(Themes.theme(family: "nope", dark: false).id, "cobalt2-dark")
        for theme in Themes.all { XCTAssertEqual(theme.colors.count, Token.allCases.count, theme.id) }
    }
}
